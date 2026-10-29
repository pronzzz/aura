import AppKit
import Combine

// MARK: - Model

struct WorkflowTrigger: Codable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case batteryBelow, chargerConnected, chargerDisconnected, appLaunched, appQuit, timeOfDay, meetingSoon, auraLaunched
        var id: String { rawValue }

        var title: String {
            switch self {
            case .batteryBelow: return "Battery drops below…"
            case .chargerConnected: return "Charger connected"
            case .chargerDisconnected: return "Charger disconnected"
            case .appLaunched: return "App launches"
            case .appQuit: return "App quits"
            case .timeOfDay: return "Every day at…"
            case .meetingSoon: return "Meeting starts soon"
            case .auraLaunched: return "Aura starts"
            }
        }

        var icon: String {
            switch self {
            case .batteryBelow: return "battery.25"
            case .chargerConnected: return "bolt.fill"
            case .chargerDisconnected: return "powerplug"
            case .appLaunched: return "app.badge"
            case .appQuit: return "xmark.app"
            case .timeOfDay: return "clock"
            case .meetingSoon: return "calendar.badge.clock"
            case .auraLaunched: return "sparkles"
            }
        }
    }

    var kind: Kind
    var number = 20
    var text = ""
    var hour = 9
    var minute = 0

    var summary: String {
        switch kind {
        case .batteryBelow: return "Battery below \(number)%"
        case .appLaunched: return "\(text.isEmpty ? "An app" : text) launches"
        case .appQuit: return "\(text.isEmpty ? "An app" : text) quits"
        case .timeOfDay: return String(format: "Every day at %02d:%02d", hour, minute)
        case .meetingSoon: return "\(number) min before a meeting"
        default: return kind.title
        }
    }
}

struct WorkflowAction: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case notify, peek, openApp, openURL, runShortcut, startTimer, addTodo, playPause, pauseMusic, openNotch, appleScript
        var id: String { rawValue }

        var title: String {
            switch self {
            case .notify: return "Show notification"
            case .peek: return "Quick Peek message"
            case .openApp: return "Open app"
            case .openURL: return "Open URL"
            case .runShortcut: return "Run shortcut"
            case .startTimer: return "Start timer"
            case .addTodo: return "Add task"
            case .playPause: return "Play / pause music"
            case .pauseMusic: return "Pause music"
            case .openNotch: return "Open the notch"
            case .appleScript: return "Run AppleScript"
            }
        }

        var icon: String {
            switch self {
            case .notify: return "bell.badge"
            case .peek: return "capsule.tophalf.filled"
            case .openApp: return "app"
            case .openURL: return "link"
            case .runShortcut: return "square.stack.3d.up"
            case .startTimer: return "timer"
            case .addTodo: return "checklist"
            case .playPause: return "playpause"
            case .pauseMusic: return "pause"
            case .openNotch: return "rectangle.topthird.inset.filled"
            case .appleScript: return "applescript"
            }
        }

        var textLabel: String? {
            switch self {
            case .notify, .peek: return "Message"
            case .openApp: return "App name"
            case .openURL: return "URL"
            case .runShortcut: return "Shortcut name"
            case .startTimer: return "Label"
            case .addTodo: return "Task"
            case .appleScript: return "Script"
            default: return nil
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var text = ""
    var number = 5

    var summary: String {
        switch kind {
        case .startTimer: return "Start a \(number) min timer" + (text.isEmpty ? "" : " “\(text)”")
        case .playPause, .pauseMusic, .openNotch: return kind.title
        default: return text.isEmpty ? kind.title : "\(kind.title): \(text)"
        }
    }
}

struct Workflow: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var isEnabled = true
    var trigger: WorkflowTrigger
    var actions: [WorkflowAction]
    var lastRun: Date?

    static let templates: [Workflow] = [
        Workflow(name: "Low battery warning",
                 trigger: WorkflowTrigger(kind: .batteryBelow, number: 15),
                 actions: [WorkflowAction(kind: .notify, text: "Battery is low — plug in soon.")]),
        Workflow(name: "Meeting heads-up",
                 trigger: WorkflowTrigger(kind: .meetingSoon, number: 2),
                 actions: [WorkflowAction(kind: .pauseMusic), WorkflowAction(kind: .openNotch)]),
        Workflow(name: "Deep work with Xcode",
                 trigger: WorkflowTrigger(kind: .appLaunched, text: "Xcode"),
                 actions: [WorkflowAction(kind: .startTimer, text: "Focus", number: 50)]),
        Workflow(name: "Morning start",
                 trigger: WorkflowTrigger(kind: .timeOfDay, hour: 9, minute: 0),
                 actions: [WorkflowAction(kind: .peek, text: "Good morning! Here's your day."), WorkflowAction(kind: .openNotch)]),
        Workflow(name: "Unplugged reminder",
                 trigger: WorkflowTrigger(kind: .chargerDisconnected),
                 actions: [WorkflowAction(kind: .peek, text: "Running on battery")]),
    ]
}

// MARK: - Engine

/// Runs user workflows ("when X happens, do Y") entirely on-device.
@MainActor
final class WorkflowEngine: ObservableObject {
    static let shared = WorkflowEngine()

    @Published var workflows: [Workflow] = [] { didSet { persist() } }

    private let storageKey = "aura.workflows.v2"
    private var cancellables = Set<AnyCancellable>()
    private var fired = Set<String>()
    private var minuteTimer: Timer?
    private var started = false

    private init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let saved = try? JSONDecoder().decode([Workflow].self, from: data) {
            workflows = saved
        }
    }

    func start() {
        guard !started else { return }
        started = true

        PowerService.shared.events
            .sink { [weak self] event in
                switch event {
                case .pluggedIn: self?.fire(.chargerConnected)
                case .unplugged: self?.fire(.chargerDisconnected)
                default: break
                }
            }
            .store(in: &cancellables)

        PowerService.shared.$level.removeDuplicates()
            .sink { [weak self] level in self?.checkBattery(level) }
            .store(in: &cancellables)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.fireApp(.appLaunched, app) }
        }
        center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated { self?.fireApp(.appQuit, app) }
        }

        minuteTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkClock() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.fire(.auraLaunched) }
    }

    // MARK: Editing

    func add(_ workflow: Workflow) { workflows.append(workflow) }

    func update(_ workflow: Workflow) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) { workflows[index] = workflow }
    }

    func remove(_ id: UUID) { workflows.removeAll { $0.id == id } }

    func setEnabled(_ id: UUID, _ enabled: Bool) {
        if let index = workflows.firstIndex(where: { $0.id == id }) { workflows[index].isEnabled = enabled }
    }

    // MARK: Running

    func run(_ workflow: Workflow) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) { workflows[index].lastRun = Date() }
        Task {
            for action in workflow.actions { await perform(action) }
        }
    }

    private func perform(_ action: WorkflowAction) async {
        switch action.kind {
        case .notify:
            NotificationPresenter.post(title: "Aura", body: action.text.isEmpty ? "Workflow ran." : action.text)
        case .peek:
            ActivityCenter.shared.showPeek(Peek(kind: .info, title: action.text.isEmpty ? "Aura" : action.text,
                                                subtitle: "Workflow", icon: "sparkles", tint: .purple), duration: 4)
        case .openApp:
            AppLauncher.open(named: action.text)
        case .openURL:
            if let url = URL(string: action.text) { NSWorkspace.shared.open(url) }
        case .runShortcut:
            ShortcutsService.shared.run(action.text)
        case .startTimer:
            TimerService.shared.start(seconds: TimeInterval(max(1, action.number) * 60), label: action.text)
        case .addTodo:
            TodoStore.shared.add(action.text)
        case .playPause:
            NowPlayingService.shared.togglePlayPause()
        case .pauseMusic:
            if NowPlayingService.shared.isPlaying { NowPlayingService.shared.togglePlayPause() }
        case .openNotch:
            NotchCoordinator.shared.open(tab: .nook)
        case .appleScript:
            let source = action.text
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    var error: NSDictionary?
                    NSAppleScript(source: source)?.executeAndReturnError(&error)
                    continuation.resume()
                }
            }
        }
        // Small gap so sequential actions feel deliberate.
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    // MARK: Triggers

    private func fire(_ kind: WorkflowTrigger.Kind, matching: (WorkflowTrigger) -> Bool = { _ in true }) {
        for workflow in workflows where workflow.isEnabled && workflow.trigger.kind == kind && matching(workflow.trigger) {
            run(workflow)
        }
    }

    private func fireApp(_ kind: WorkflowTrigger.Kind, _ app: NSRunningApplication?) {
        guard let app else { return }
        let name = app.localizedName?.lowercased() ?? ""
        let bundle = app.bundleIdentifier?.lowercased() ?? ""
        fire(kind) { trigger in
            let target = trigger.text.lowercased().trimmingCharacters(in: .whitespaces)
            return !target.isEmpty && (target == name || target == bundle)
        }
    }

    private func checkBattery(_ level: Int) {
        guard PowerService.shared.hasBattery else { return }
        for workflow in workflows where workflow.isEnabled && workflow.trigger.kind == .batteryBelow {
            let key = "battery-\(workflow.id)"
            if level < workflow.trigger.number, !PowerService.shared.isPluggedIn {
                if !fired.contains(key) {
                    fired.insert(key)
                    run(workflow)
                }
            } else if level >= workflow.trigger.number + 3 {
                fired.remove(key) // re-arm
            }
        }
    }

    private func checkClock() {
        let now = Date()
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: now)
        let day = "\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"

        for workflow in workflows where workflow.isEnabled {
            switch workflow.trigger.kind {
            case .timeOfDay:
                let key = "time-\(workflow.id)-\(day)"
                if parts.hour == workflow.trigger.hour, parts.minute == workflow.trigger.minute, !fired.contains(key) {
                    fired.insert(key)
                    run(workflow)
                }
            case .meetingSoon:
                guard let event = CalendarService.shared.nextEvent else { continue }
                let key = "meeting-\(workflow.id)-\(event.id)"
                let lead = TimeInterval(max(1, workflow.trigger.number) * 60)
                let untilStart = event.start.timeIntervalSince(now)
                if untilStart > 0, untilStart <= lead, !fired.contains(key) {
                    fired.insert(key)
                    run(workflow)
                }
            default:
                continue
            }
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(workflows) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
