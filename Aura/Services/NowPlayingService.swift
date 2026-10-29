import AppKit
import Combine
import CoreImage

enum MediaSource: String, Equatable {
    case spotify, music, web, none

    var bundleID: String? {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        case .web, .none: return nil
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        case .web: return "Web Player"
        case .none: return ""
        }
    }
}

struct NowPlayingTrack: Equatable {
    var title: String
    var artist: String
    var album: String
    var duration: Double
}

/// What's playing in Spotify and Apple Music (plus, optionally, browser players).
///
/// Uses Apple Events, which keep working on recent macOS where the private MediaRemote
/// framework is restricted. Spotify and Music both broadcast distributed notifications on
/// every state change, so Aura only polls occasionally to keep the scrubber in sync.
@MainActor
final class NowPlayingService: ObservableObject {
    static let shared = NowPlayingService()

    @Published private(set) var track: NowPlayingTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var source: MediaSource = .none
    @Published private(set) var artwork: NSImage?
    @Published private(set) var accent: NSColor = .white
    @Published private(set) var lastActive = Date.distantPast
    /// Bumps whenever the scrubber should be redrawn from fresh data.
    @Published private(set) var syncStamp = Date()

    /// Fires when a new song starts.
    let trackChanged = PassthroughSubject<NowPlayingTrack, Never>()

    private var basePosition: Double = 0
    private var baseDate = Date()
    private let worker = ScriptWorker()
    private var pollTimer: Timer?
    private var started = false
    private var artworkKey = ""

    private init() {}

    var duration: Double { track?.duration ?? 0 }

    var position: Double {
        guard isPlaying else { return basePosition }
        return min(max(duration, 0), basePosition + Date().timeIntervalSince(baseDate))
    }

    /// Playing, or paused only moments ago.
    var isActive: Bool {
        guard track != nil else { return false }
        return isPlaying || Date().timeIntervalSince(lastActive) < Pref.double(.activityLinger)
    }

    func start() {
        guard !started else { return }
        started = true

        let distributed = DistributedNotificationCenter.default()
        for name in ["com.spotify.client.PlaybackStateChanged", "com.apple.Music.playerInfo"] {
            distributed.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(after: 0.15) }
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh(after: 1.0) }
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    // MARK: - Reading

    func refresh(after delay: TimeInterval = 0) {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let includeWeb = Pref.bool(.webMediaDetection)
        let current = source
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [worker] in
            worker.async {
                var snapshots: [MediaSnapshot] = []
                if running.contains(MediaSource.spotify.bundleID!), let s = MediaScripts.spotify(worker) { snapshots.append(s) }
                if running.contains(MediaSource.music.bundleID!), let s = MediaScripts.music(worker) { snapshots.append(s) }
                if includeWeb, !snapshots.contains(where: \.isPlaying), let s = MediaScripts.web(worker, running: running) {
                    snapshots.append(s)
                }
                let pick = snapshots.first(where: \.isPlaying)
                    ?? snapshots.first(where: { $0.source == current })
                    ?? snapshots.first
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { NowPlayingService.shared.apply(pick) }
                }
            }
        }
    }

    private func apply(_ snapshot: MediaSnapshot?) {
        guard let snapshot else {
            if track != nil {
                track = nil
                isPlaying = false
                source = .none
                artwork = nil
                artworkKey = ""
            }
            return
        }

        let wasPlaying = isPlaying
        let previous = track
        source = snapshot.source
        isPlaying = snapshot.isPlaying
        basePosition = snapshot.position
        baseDate = Date()
        syncStamp = Date()
        if isPlaying || wasPlaying { lastActive = Date() }

        if snapshot.track != previous {
            track = snapshot.track
            loadArtwork(for: snapshot)
            if snapshot.isPlaying, previous?.title != snapshot.track.title {
                trackChanged.send(snapshot.track)
            }
        }
    }

    private func loadArtwork(for snapshot: MediaSnapshot) {
        let key = "\(snapshot.source.rawValue)|\(snapshot.track.title)|\(snapshot.track.album)"
        guard key != artworkKey else { return }
        artworkKey = key

        switch snapshot.source {
        case .spotify:
            guard let url = snapshot.artworkURL else { setArtwork(nil, key: key); return }
            Task {
                let data = try? await URLSession.shared.data(from: url).0
                self.setArtwork(data.flatMap(NSImage.init(data:)), key: key)
            }
        case .music:
            worker.async { [worker] in
                let data = MediaScripts.musicArtwork(worker)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        NowPlayingService.shared.setArtwork(data.flatMap(NSImage.init(data:)), key: key)
                    }
                }
            }
        case .web, .none:
            setArtwork(nil, key: key)
        }
    }

    private func setArtwork(_ image: NSImage?, key: String) {
        guard key == artworkKey else { return }
        artwork = image
        accent = image?.vibrantAverageColor ?? .white
    }

    // MARK: - Controls

    func togglePlayPause() {
        basePosition = position
        baseDate = Date()
        isPlaying.toggle()
        if isPlaying { lastActive = Date() }
        send("playpause")
    }

    func next() { send("next track") }
    func previous() { send("previous track") }

    func seek(to seconds: Double) {
        basePosition = max(0, min(duration, seconds))
        baseDate = Date()
        syncStamp = Date()
        send("set player position to \(String(format: "%.2f", basePosition))")
    }

    func openSourceApp() {
        guard let id = source.bundleID ?? MediaSource.music.bundleID,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    func launch(_ source: MediaSource) {
        guard let id = source.bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    static func isInstalled(_ source: MediaSource) -> Bool {
        guard let id = source.bundleID else { return false }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil
    }

    private func send(_ command: String) {
        guard let id = source.bundleID else {
            MediaKeys.post(command)
            return
        }
        worker.async { [worker] in
            _ = worker.run("tell application id \"\(id)\" to \(command)")
        }
        refresh(after: 0.35)
    }

    // MARK: - Demo data (snapshots)

    func applyDemo(track: NowPlayingTrack, playing: Bool, position: Double, artwork: NSImage?, source: MediaSource) {
        self.track = track
        self.isPlaying = playing
        self.source = source
        self.basePosition = position
        self.baseDate = Date()
        self.artwork = artwork
        self.accent = artwork?.vibrantAverageColor ?? .white
        self.lastActive = Date()
    }
}

// MARK: - AppleScript plumbing

struct MediaSnapshot {
    var source: MediaSource
    var isPlaying: Bool
    var track: NowPlayingTrack
    var position: Double
    var artworkURL: URL?
}

/// Serial queue that owns compiled AppleScripts (NSAppleScript isn't thread-safe).
final class ScriptWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.pranavdwivedi.aura.scripts", qos: .userInitiated)
    private var cache: [String: NSAppleScript] = [:]

    func async(_ block: @escaping () -> Void) { queue.async(execute: block) }

    /// Must be called on the worker queue.
    func run(_ source: String) -> NSAppleEventDescriptor? {
        let script: NSAppleScript
        if let cached = cache[source] {
            script = cached
        } else {
            guard let compiled = NSAppleScript(source: source) else { return nil }
            cache[source] = compiled
            script = compiled
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}

enum MediaScripts {
    private static let separator = "\u{1F}"

    static func spotify(_ worker: ScriptWorker) -> MediaSnapshot? {
        let source = """
        set sep to character id 31
        tell application id "com.spotify.client"
            try
                set st to player state as string
                if st is "stopped" then return "stopped"
                set t to current track
                return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & (((duration of t) / 1000) as string) & sep & ((player position) as string) & sep & (artwork url of t)
            on error
                return "stopped"
            end try
        end tell
        """
        return parse(worker.run(source)?.stringValue, source: .spotify)
    }

    static func music(_ worker: ScriptWorker) -> MediaSnapshot? {
        let source = """
        set sep to character id 31
        tell application id "com.apple.Music"
            try
                set st to player state as string
                if st is "stopped" then return "stopped"
                set t to current track
                return st & sep & (name of t) & sep & (artist of t) & sep & (album of t) & sep & ((duration of t) as string) & sep & ((player position) as string) & sep & ""
            on error
                return "stopped"
            end try
        end tell
        """
        return parse(worker.run(source)?.stringValue, source: .music)
    }

    static func musicArtwork(_ worker: ScriptWorker) -> Data? {
        let source = """
        tell application id "com.apple.Music"
            try
                return raw data of artwork 1 of current track
            on error
                return ""
            end try
        end tell
        """
        guard let descriptor = worker.run(source) else { return nil }
        let data = descriptor.data
        return data.count > 32 ? data : nil
    }

    /// Reads tab titles of YouTube Music / Spotify Web in common browsers. Opt-in.
    static func web(_ worker: ScriptWorker, running: Set<String>) -> MediaSnapshot? {
        let chromium = ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac", "com.brave.Browser"]
        var titles: [String] = []
        for id in chromium where running.contains(id) {
            let source = """
            set out to ""
            tell application id "\(id)"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (title of t) & linefeed
                    end repeat
                end repeat
            end tell
            return out
            """
            titles += (worker.run(source)?.stringValue ?? "").components(separatedBy: "\n")
        }
        if running.contains("com.apple.Safari") {
            let source = """
            set out to ""
            tell application id "com.apple.Safari"
                repeat with w in windows
                    repeat with t in tabs of w
                        set out to out & (name of t) & linefeed
                    end repeat
                end repeat
            end tell
            return out
            """
            titles += (worker.run(source)?.stringValue ?? "").components(separatedBy: "\n")
        }

        for title in titles {
            if let range = title.range(of: " - YouTube Music") {
                let parts = title[..<range.lowerBound].components(separatedBy: " - ")
                return webSnapshot(title: parts.first ?? "", artist: parts.count > 1 ? parts[1] : "YouTube Music")
            }
            if title.contains("•"), let range = title.range(of: " - Spotify") ?? title.range(of: " | Spotify") {
                let parts = title[..<range.lowerBound].components(separatedBy: " • ")
                return webSnapshot(title: parts.first ?? "", artist: parts.count > 1 ? parts[1] : "Spotify Web")
            }
        }
        return nil
    }

    private static func webSnapshot(title: String, artist: String) -> MediaSnapshot? {
        let clean = title.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return nil }
        return MediaSnapshot(source: .web, isPlaying: true,
                             track: NowPlayingTrack(title: clean, artist: artist, album: "", duration: 0),
                             position: 0, artworkURL: nil)
    }

    private static func parse(_ output: String?, source: MediaSource) -> MediaSnapshot? {
        guard let output, output != "stopped" else { return nil }
        let fields = output.components(separatedBy: separator)
        guard fields.count >= 6 else { return nil }
        func number(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let track = NowPlayingTrack(title: fields[1], artist: fields[2], album: fields[3], duration: number(fields[4]))
        let artwork = fields.count > 6 ? URL(string: fields[6]) : nil
        return MediaSnapshot(source: source, isPlaying: fields[0] == "playing", track: track,
                             position: number(fields[5]), artworkURL: artwork)
    }
}

/// System media keys, used for sources Aura can't script directly.
enum MediaKeys {
    static func post(_ command: String) {
        let key: Int32
        switch command {
        case "playpause": key = 16
        case "next track": key = 17
        case "previous track": key = 18
        default: return
        }
        for down in [true, false] {
            let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
            let data1 = Int((key << 16) | ((down ? 0xA : 0xB) << 8))
            NSEvent.otherEvent(with: .systemDefined, location: .zero, modifierFlags: flags, timestamp: 0,
                               windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}

extension NSImage {
    /// Average colour of the image, nudged brighter so it reads well on black.
    var vibrantAverageColor: NSColor? {
        guard let tiff = tiffRepresentation, let input = CIImage(data: tiff) else { return nil }
        let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: input,
                                                                    kCIInputExtentKey: CIVector(cgRect: input.extent)])
        guard let output = filter?.outputImage else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        CIContext(options: [.workingColorSpace: NSNull()]).render(output, toBitmap: &pixel, rowBytes: 4,
                                                                  bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                                                  format: .RGBA8, colorSpace: nil)
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        guard let hsb = color.usingColorSpace(.deviceRGB) else { return color }
        return NSColor(hue: hsb.hueComponent,
                       saturation: min(1, hsb.saturationComponent * 1.25),
                       brightness: max(0.75, hsb.brightnessComponent),
                       alpha: 1)
    }
}
