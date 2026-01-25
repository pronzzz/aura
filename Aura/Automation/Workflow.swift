import Foundation
import Combine

/// Represents an automated workflow with triggers, conditions, and actions
struct Workflow: Identifiable, Codable {
    let id: UUID
    var name: String
    var description: String
    var isEnabled: Bool
    var trigger: WorkflowTrigger
    var conditions: [WorkflowCondition]
    var actions: [WorkflowAction]
    var createdAt: Date
    var lastRun: Date?
    var runCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String = "",
        isEnabled: Bool = true,
        trigger: WorkflowTrigger,
        conditions: [WorkflowCondition] = [],
        actions: [WorkflowAction]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.conditions = conditions
        self.actions = actions
        self.createdAt = Date()
        self.lastRun = nil
        self.runCount = 0
    }
}

// MARK: - Triggers

enum WorkflowTrigger: Codable {
    case appLaunched(bundleId: String)
    case appClosed(bundleId: String)
    case timeOfDay(hour: Int, minute: Int)
    case batteryLevel(below: Int)
    case batteryCharging(started: Bool)
    case focusModeChanged(active: Bool)
    case meetingStarting(minutesBefore: Int)
    case screenShareStarted
    case screenShareEnded
    case hotkey(keyCode: Int, modifiers: Int)
    case manual
    
    var displayName: String {
        switch self {
        case .appLaunched(let bundleId):
            return "App Launched: \(bundleId)"
        case .appClosed(let bundleId):
            return "App Closed: \(bundleId)"
        case .timeOfDay(let hour, let minute):
            return String(format: "At %02d:%02d", hour, minute)
        case .batteryLevel(let below):
            return "Battery Below \(below)%"
        case .batteryCharging(let started):
            return started ? "Charging Started" : "Unplugged"
        case .focusModeChanged(let active):
            return active ? "Focus Mode On" : "Focus Mode Off"
        case .meetingStarting(let minutes):
            return "\(minutes)min Before Meeting"
        case .screenShareStarted:
            return "Screen Share Started"
        case .screenShareEnded:
            return "Screen Share Ended"
        case .hotkey:
            return "Hotkey Pressed"
        case .manual:
            return "Run Manually"
        }
    }
}

// MARK: - Conditions

enum WorkflowCondition: Codable {
    case timeRange(startHour: Int, endHour: Int)
    case dayOfWeek(days: [Int])  // 1 = Sunday, 7 = Saturday
    case appIsRunning(bundleId: String)
    case appIsNotRunning(bundleId: String)
    case batteryAbove(percent: Int)
    case isCharging
    case isNotCharging
    case focusModeActive
    case focusModeInactive
    case isWorkHours
    
    func evaluate(context: ContextSnapshot) -> Bool {
        switch self {
        case .timeRange(let start, let end):
            let hour = Calendar.current.component(.hour, from: Date())
            return hour >= start && hour < end
            
        case .dayOfWeek(let days):
            let weekday = Calendar.current.component(.weekday, from: Date())
            return days.contains(weekday)
            
        case .appIsRunning(let bundleId):
            return context.currentApp?.bundleIdentifier == bundleId
            
        case .appIsNotRunning(let bundleId):
            return context.currentApp?.bundleIdentifier != bundleId
            
        case .batteryAbove(let percent):
            return context.batteryLevel > percent
            
        case .isCharging:
            return context.isCharging
            
        case .isNotCharging:
            return !context.isCharging
            
        case .focusModeActive:
            return context.isFocusMode
            
        case .focusModeInactive:
            return !context.isFocusMode
            
        case .isWorkHours:
            return context.isWorkHours
        }
    }
}

// MARK: - Actions

enum WorkflowAction: Codable {
    case showWidget(widgetName: String)
    case hideWidget(widgetName: String)
    case setWidgetPriority(widgetName: String, priority: Int)
    case expandNotch
    case collapseNotch
    case showNotification(title: String, body: String)
    case runShortcut(name: String)
    case openURL(url: String)
    case openApp(bundleId: String)
    case runAppleScript(script: String)
    case delay(seconds: Double)
    
    var displayName: String {
        switch self {
        case .showWidget(let name): return "Show \(name) Widget"
        case .hideWidget(let name): return "Hide \(name) Widget"
        case .setWidgetPriority(let name, _): return "Prioritize \(name)"
        case .expandNotch: return "Expand Notch"
        case .collapseNotch: return "Collapse Notch"
        case .showNotification(let title, _): return "Notify: \(title)"
        case .runShortcut(let name): return "Run Shortcut: \(name)"
        case .openURL(let url): return "Open URL: \(url)"
        case .openApp(let bundleId): return "Open App: \(bundleId)"
        case .runAppleScript: return "Run AppleScript"
        case .delay(let seconds): return "Wait \(seconds)s"
        }
    }
}

// MARK: - Preset Workflows

extension Workflow {
    static var presets: [Workflow] {
        [
            // Work mode when opening productivity apps
            Workflow(
                name: "Work Mode",
                description: "Enable focus when opening Xcode or VS Code",
                trigger: .appLaunched(bundleId: "com.apple.dt.Xcode"),
                actions: [
                    .showWidget(widgetName: "System"),
                    .showWidget(widgetName: "Calendar"),
                    .collapseNotch
                ]
            ),
            
            // Presentation mode
            Workflow(
                name: "Presentation Mode",
                description: "Minimize distractions when screen sharing",
                trigger: .screenShareStarted,
                actions: [
                    .collapseNotch,
                    .hideWidget(widgetName: "Music"),
                    .hideWidget(widgetName: "System")
                ]
            ),
            
            // Low battery alert
            Workflow(
                name: "Low Battery Alert",
                description: "Show battery widget when power is low",
                trigger: .batteryLevel(below: 20),
                conditions: [.isNotCharging],
                actions: [
                    .showWidget(widgetName: "Battery"),
                    .setWidgetPriority(widgetName: "Battery", priority: 100),
                    .showNotification(title: "Low Battery", body: "Consider plugging in your charger")
                ]
            ),
            
            // Meeting prep
            Workflow(
                name: "Meeting Prep",
                description: "Prepare for upcoming meeting",
                trigger: .meetingStarting(minutesBefore: 5),
                actions: [
                    .showWidget(widgetName: "Calendar"),
                    .expandNotch,
                    .showNotification(title: "Meeting Soon", body: "Your meeting starts in 5 minutes")
                ]
            ),
            
            // End of day
            Workflow(
                name: "End of Day",
                description: "Wind down after work hours",
                trigger: .timeOfDay(hour: 18, minute: 0),
                conditions: [.dayOfWeek(days: [2, 3, 4, 5, 6])],  // Mon-Fri
                actions: [
                    .showWidget(widgetName: "Music"),
                    .hideWidget(widgetName: "System"),
                    .expandNotch
                ]
            )
        ]
    }
}
