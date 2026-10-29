import AppKit
import Combine

// MARK: - Timers

struct AuraTimer: Identifiable, Codable, Equatable {
    var id = UUID()
    var label: String
    var duration: TimeInterval
    var endDate: Date?
    var pausedRemaining: TimeInterval?

    var isRunning: Bool { endDate != nil }

    func remaining(at now: Date) -> TimeInterval {
        if let endDate { return max(0, endDate.timeIntervalSince(now)) }
        return pausedRemaining ?? duration
    }

    func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - remaining(at: now) / duration
    }
}

@MainActor
final class TimerService: ObservableObject {
    static let shared = TimerService()

    @Published private(set) var timers: [AuraTimer] = [] { didSet { persist() } }
    @Published private(set) var now = Date()

    private var ticker: Timer?
    private let storageKey = "aura.timers"

    private init() {}

    var hasRunning: Bool { timers.contains(where: \.isRunning) }

    /// The running timer that ends soonest (shown in the live activity).
    var primary: AuraTimer? {
        timers.filter(\.isRunning).min { $0.remaining(at: now) < $1.remaining(at: now) }
    }

    func restore() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([AuraTimer].self, from: data) else { return }
        timers = saved
        updateTicker()
        tick()
    }

    @discardableResult
    func start(seconds: TimeInterval, label: String? = nil) -> AuraTimer {
        let name = label?.isEmpty == false ? label! : Self.defaultLabel(for: seconds)
        let timer = AuraTimer(label: name, duration: seconds, endDate: Date().addingTimeInterval(seconds))
        timers.append(timer)
        updateTicker()
        return timer
    }

    func pause(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), timers[index].isRunning else { return }
        timers[index].pausedRemaining = timers[index].remaining(at: Date())
        timers[index].endDate = nil
        updateTicker()
    }

    func resume(_ id: UUID) {
        guard let index = timers.firstIndex(where: { $0.id == id }), !timers[index].isRunning else { return }
        let remaining = timers[index].pausedRemaining ?? timers[index].duration
        timers[index].endDate = Date().addingTimeInterval(remaining)
        timers[index].pausedRemaining = nil
        updateTicker()
    }

    func addTime(_ id: UUID, seconds: TimeInterval) {
        guard let index = timers.firstIndex(where: { $0.id == id }) else { return }
        timers[index].duration += seconds
        if let end = timers[index].endDate {
            timers[index].endDate = end.addingTimeInterval(seconds)
        } else {
            timers[index].pausedRemaining = (timers[index].pausedRemaining ?? 0) + seconds
        }
    }

    func cancel(_ id: UUID) {
        timers.removeAll { $0.id == id }
        updateTicker()
    }

    func applyDemo(_ demo: [AuraTimer]) {
        timers = demo
        now = Date()
    }

    private func updateTicker() {
        if timers.isEmpty {
            ticker?.invalidate()
            ticker = nil
        } else if ticker == nil {
            ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        }
    }

    private func tick() {
        now = Date()
        let finished = timers.filter { $0.isRunning && $0.remaining(at: now) <= 0 }
        guard !finished.isEmpty else { return }
        timers.removeAll { timer in finished.contains { $0.id == timer.id } }
        updateTicker()
        for timer in finished {
            NSSound(named: "Glass")?.play()
            ActivityCenter.shared.showPeek(Peek(kind: .timer, title: "\(timer.label) finished",
                                                subtitle: Self.format(timer.duration) + " timer",
                                                icon: "timer", tint: .orange), duration: 5)
            NotificationPresenter.post(title: "\(timer.label) finished", body: "Your \(Self.format(timer.duration)) timer is done.")
        }
    }

    private func persist() {
        guard !Runtime.isSnapshot else { return }
        if let data = try? JSONEncoder().encode(timers) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func defaultLabel(for seconds: TimeInterval) -> String {
        seconds == 25 * 60 ? "Focus" : "Timer"
    }

    static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Todos

struct TodoItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var isDone = false
    var created = Date()
}

@MainActor
final class TodoStore: ObservableObject {
    static let shared = TodoStore()

    @Published private(set) var items: [TodoItem] = [] { didSet { persist() } }
    private let storageKey = "aura.todos"

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([TodoItem].self, from: data) {
            items = saved
        }
    }

    var openCount: Int { items.filter { !$0.isDone }.count }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(TodoItem(text: trimmed), at: 0)
    }

    func toggle(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isDone.toggle()
        // Keep open items on top.
        items.sort { !$0.isDone && $1.isDone }
    }

    func remove(_ id: UUID) { items.removeAll { $0.id == id } }
    func clearDone() { items.removeAll(where: \.isDone) }
    func applyDemo(_ demo: [TodoItem]) { items = demo }

    private func persist() {
        guard !Runtime.isSnapshot else { return }
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

// MARK: - Shortcuts

@MainActor
final class ShortcutsService: ObservableObject {
    static let shared = ShortcutsService()

    @Published private(set) var all: [String] = []
    @Published private(set) var isLoading = false
    @Published var favorites: [String] = Pref.strings(.favoriteShortcuts) {
        didSet { Pref.set(favorites, .favoriteShortcuts) }
    }

    private init() {}

    func load() async {
        isLoading = true
        let output = await Self.shell(["list"])
        all = output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.sorted()
        isLoading = false
    }

    func toggleFavorite(_ name: String) {
        if let index = favorites.firstIndex(of: name) { favorites.remove(at: index) } else { favorites.append(name) }
    }

    func run(_ name: String) {
        Task.detached { _ = await ShortcutsService.shell(["run", name]) }
    }

    nonisolated static func shell(_ arguments: [String]) async -> String {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
                process.arguments = arguments
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = Pipe()
                do {
                    try process.run()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } catch {
                    continuation.resume(returning: "")
                }
            }
        }
    }
}
