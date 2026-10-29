import Foundation

/// Typed access to Aura's preferences. Views bind with `@AppStorage(Pref.Key.x.rawValue)`.
enum Pref {
    enum Key: String, CaseIterable {
        // Notch behaviour
        case openOnHover
        case hoverDelay
        case hapticsEnabled
        case gesturesEnabled
        case invertMediaGestures
        case hideInFullscreen
        case displayMode
        case showFakeNotch
        case defaultTab
        case rememberLastTab
        case lastTab

        // Live activities & peeks
        case musicActivity
        case batteryActivity
        case timerActivity
        case activityLinger
        case lowBatteryThreshold
        case quickPeekEnabled
        case peekOnSongChange
        case peekOnPower
        case peekOnMeetings
        case meetingPeekMinutes
        case colorfulSpectrum

        // Media
        case webMediaDetection

        // Assistant
        case ollamaURL
        case ollamaModel

        // App
        case favoriteShortcuts
        case showMenuBarIcon
        case checkForUpdates
        case onboardingDone
        case hotKeysEnabled
    }

    static let defaults: [Key: Any] = [
        .openOnHover: true,
        .hoverDelay: 0.12,
        .hapticsEnabled: true,
        .gesturesEnabled: true,
        .invertMediaGestures: false,
        .hideInFullscreen: true,
        .displayMode: DisplayMode.notched.rawValue,
        .showFakeNotch: true,
        .defaultTab: NotchTab.nook.rawValue,
        .rememberLastTab: true,
        .lastTab: NotchTab.nook.rawValue,

        .musicActivity: true,
        .batteryActivity: true,
        .timerActivity: true,
        .activityLinger: 4.0,
        .lowBatteryThreshold: 20,
        .quickPeekEnabled: true,
        .peekOnSongChange: true,
        .peekOnPower: true,
        .peekOnMeetings: true,
        .meetingPeekMinutes: 5,
        .colorfulSpectrum: true,

        .webMediaDetection: false,

        .ollamaURL: "http://localhost:11434",
        .ollamaModel: "llama3.2",

        .favoriteShortcuts: [String](),
        .showMenuBarIcon: true,
        .checkForUpdates: true,
        .onboardingDone: false,
        .hotKeysEnabled: true,
    ]

    static func registerDefaults() {
        var values: [String: Any] = [:]
        for (key, value) in defaults { values[key.rawValue] = value }
        UserDefaults.standard.register(defaults: values)
    }

    static func bool(_ key: Key) -> Bool { UserDefaults.standard.bool(forKey: key.rawValue) }
    static func double(_ key: Key) -> Double { UserDefaults.standard.double(forKey: key.rawValue) }
    static func int(_ key: Key) -> Int { UserDefaults.standard.integer(forKey: key.rawValue) }
    static func string(_ key: Key) -> String { UserDefaults.standard.string(forKey: key.rawValue) ?? "" }
    static func strings(_ key: Key) -> [String] { UserDefaults.standard.stringArray(forKey: key.rawValue) ?? [] }
    static func set(_ value: Any?, _ key: Key) { UserDefaults.standard.set(value, forKey: key.rawValue) }
}

enum DisplayMode: String, CaseIterable, Identifiable {
    case notched, primary, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .notched: return "Built-in (notch) display"
        case .primary: return "Primary display"
        case .all: return "All displays"
        }
    }
}

enum NotchTab: String, CaseIterable, Identifiable {
    case nook, tray, tasks, ask
    var id: String { rawValue }
    var title: String {
        switch self {
        case .nook: return "Nook"
        case .tray: return "Tray"
        case .tasks: return "Tasks"
        case .ask: return "Ask"
        }
    }
    var icon: String {
        switch self {
        case .nook: return "square.grid.2x2.fill"
        case .tray: return "tray.full.fill"
        case .tasks: return "checklist"
        case .ask: return "sparkles"
        }
    }
}

enum Runtime {
    /// True while `--snapshot` renders demo data; disables all persistence.
    nonisolated(unsafe) static var isSnapshot = false
}
