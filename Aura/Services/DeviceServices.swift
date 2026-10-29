import AppKit
import AVFoundation
import Combine
import Darwin
import SwiftUI

// MARK: - Mirror (camera)

/// Camera preview for a quick look before a call. Runs only while the Mirror is visible.
final class CameraService: NSObject, ObservableObject, @unchecked Sendable {
    static let shared = CameraService()

    let session = AVCaptureSession()
    @Published private(set) var authorization = AVCaptureDevice.authorizationStatus(for: .video)
    @Published private(set) var isRunning = false

    private let queue = DispatchQueue(label: "com.pranavdwivedi.aura.camera")
    private var configured = false

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    self.authorization = AVCaptureDevice.authorizationStatus(for: .video)
                    if granted { self.run() }
                }
            }
        default:
            authorization = AVCaptureDevice.authorizationStatus(for: .video)
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    private func run() {
        authorization = .authorized
        queue.async {
            if !self.configured {
                self.session.beginConfiguration()
                self.session.sessionPreset = .high
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device),
                   self.session.canAddInput(input) {
                    self.session.addInput(input)
                }
                self.session.commitConfiguration()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
            DispatchQueue.main.async { self.isRunning = self.session.isRunning }
        }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: PreviewView, context: Context) {}

    final class PreviewView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            previewLayer.videoGravity = .resizeAspectFill
            layer = previewLayer
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}

// MARK: - System stats

/// CPU and memory load, sampled only while something is showing them.
@MainActor
final class SystemStatsService: ObservableObject {
    static let shared = SystemStatsService()

    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0

    private var timer: Timer?
    private var users = 0
    private var previous: host_cpu_load_info?

    private init() {}

    func acquire() {
        users += 1
        guard timer == nil else { return }
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
    }

    func release() {
        users = max(0, users - 1)
        if users == 0 {
            timer?.invalidate()
            timer = nil
        }
    }

    func applyDemo(cpu: Double, memory: Double) {
        self.cpu = cpu
        self.memory = memory
    }

    private func sample() {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_cpu_load_info()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &size)
            }
        }
        if result == KERN_SUCCESS {
            if let previous {
                let user = Double(info.cpu_ticks.0 &- previous.cpu_ticks.0)
                let system = Double(info.cpu_ticks.1 &- previous.cpu_ticks.1)
                let idle = Double(info.cpu_ticks.2 &- previous.cpu_ticks.2)
                let nice = Double(info.cpu_ticks.3 &- previous.cpu_ticks.3)
                let total = user + system + idle + nice
                if total > 0 { cpu = (user + system + nice) / total }
            }
            previous = info
        }

        var vmSize = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var vm = vm_statistics64()
        let vmResult = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmSize)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmSize)
            }
        }
        if vmResult == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            let used = (Double(vm.active_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
            memory = min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
        }
    }
}

// MARK: - Updates

/// Checks GitHub Releases for a newer version of Aura.
@MainActor
final class UpdateChecker: ObservableObject {
    static let shared = UpdateChecker()

    struct Release: Equatable {
        var version: String
        var url: URL
        var notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var isChecking = false
    @Published private(set) var lastMessage: String?

    private init() {}

    func check(userInitiated: Bool) async {
        isChecking = true
        defer { isChecking = false }

        var request = URLRequest(url: URL(string: "https://api.github.com/repos/pronzzz/aura/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let body: String?
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            let version = payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            if Self.isVersion(version, newerThan: AppInfo.version), let url = URL(string: payload.html_url) {
                let release = Release(version: version, url: url, notes: payload.body ?? "")
                let isNew = available != release
                available = release
                lastMessage = "Aura \(version) is available."
                if isNew {
                    ActivityCenter.shared.showPeek(Peek(kind: .update, title: "Aura \(version) is available",
                                                        subtitle: "Open the menu bar icon to download",
                                                        icon: "arrow.down.circle.fill", tint: .cyan), duration: 5)
                }
            } else {
                available = nil
                lastMessage = "You're up to date (Aura \(AppInfo.version))."
                if userInitiated {
                    ActivityCenter.shared.showPeek(Peek(kind: .update, title: "You're up to date",
                                                        subtitle: "Aura \(AppInfo.version)", icon: "checkmark.seal.fill",
                                                        tint: .green), duration: 3)
                }
            }
        } catch {
            lastMessage = "Couldn't check for updates."
        }
    }

    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let a = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let b = rhs.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
