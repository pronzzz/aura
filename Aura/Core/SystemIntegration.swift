import AppKit
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Fullscreen detection

/// Detects displays where another app is in fullscreen, so the notch can step aside.
@MainActor
final class FullscreenMonitor {
    static let shared = FullscreenMonitor()

    private(set) var fullscreenDisplays = Set<CGDirectDisplayID>()
    var onChange: (() -> Void)?
    private var timer: Timer?

    private init() {}

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Spaces animate; check again once the transition settles.
                    self?.check()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.check() }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        check()
    }

    func check() {
        let detected = Self.detect()
        if detected != fullscreenDisplays {
            fullscreenDisplays = detected
            onChange?()
        }
    }

    private static func detect() -> Set<CGDirectDisplayID> {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ignoredOwners: Set<String> = ["Window Server", "Dock", "Control Center", "Notification Center", "SystemUIServer"]

        var result = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let f = screen.frame
            // CGWindow bounds use a top-left origin.
            let cgFrame = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height)
            let covered = info.contains { window in
                guard (window[kCGWindowLayer as String] as? Int) == 0,
                      (window[kCGWindowOwnerPID as String] as? pid_t) != ownPID,
                      !ignoredOwners.contains(window[kCGWindowOwnerName as String] as? String ?? ""),
                      let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
                return abs(bounds.minX - cgFrame.minX) < 1 && abs(bounds.minY - cgFrame.minY) < 1
                    && abs(bounds.width - cgFrame.width) < 1 && abs(bounds.height - cgFrame.height) < 1
            }
            if covered { result.insert(id) }
        }
        return result
    }
}

// MARK: - Haptics

enum Haptics {
    static func tap() {
        guard Pref.bool(.hapticsEnabled) else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}

// MARK: - Global hot keys

/// ⌃⌥N toggles the notch, ⌃⌥A opens Ask. Uses Carbon hot keys, which need no extra permissions.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {}

    func install() {
        guard Pref.bool(.hotKeysEnabled), refs.isEmpty else { return }

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    switch id {
                    case 1: NotchCoordinator.shared.toggle(tab: nil)
                    case 2: NotchCoordinator.shared.toggle(tab: .ask)
                    default: break
                    }
                }
            }
            return noErr
        }, 1, &spec, nil, &handler)

        register(keyCode: kVK_ANSI_N, id: 1)
        register(keyCode: kVK_ANSI_A, id: 2)
    }

    func uninstall() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    private func register(keyCode: Int, id: UInt32) {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4155_5241), id: id) // 'AURA'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(controlKey | optionKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { refs.append(ref) }
    }
}

// MARK: - Launch at login

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Aura: launch at login change failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - App info

enum AppInfo {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0.0" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "" }
    static let repoURL = URL(string: "https://github.com/pronzzz/aura")!
    static let releasesURL = URL(string: "https://github.com/pronzzz/aura/releases")!
    static let issuesURL = URL(string: "https://github.com/pronzzz/aura/issues")!
}
