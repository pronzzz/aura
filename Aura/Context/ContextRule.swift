import Foundation
import UserNotifications

/// Defines a rule for contextual widget behavior
/// Rules determine widget priority, visibility, and actions based on context
struct ContextRule: Identifiable {
    let id: UUID
    var name: String
    var isEnabled: Bool
    var conditions: [ContextCondition]
    var actions: [ContextAction]
    var priority: Int  // Higher = more important
    
    init(
        id: UUID = UUID(),
        name: String,
        isEnabled: Bool = true,
        conditions: [ContextCondition],
        actions: [ContextAction],
        priority: Int = 50
    ) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.conditions = conditions
        self.actions = actions
        self.priority = priority
    }
    
    /// Check if all conditions are met
    func evaluate(context: ContextSnapshot) -> Bool {
        guard isEnabled else { return false }
        return conditions.allSatisfy { $0.evaluate(context: context) }
    }
}

/// A snapshot of current context state for rule evaluation
struct ContextSnapshot {
    let currentApp: RunningApp?
    let isFocusMode: Bool
    let isInMeeting: Bool
    let batteryLevel: Int
    let isCharging: Bool
    let isScreenSharing: Bool
    let timeOfDay: TimeOfDay
    let isWorkHours: Bool
}

// MARK: - Conditions

enum ContextCondition {
    case appIs(bundleId: String)
    case appCategory(category: AppCategory)
    case focusModeActive
    case focusModeInactive
    case inMeeting
    case notInMeeting
    case batteryBelow(percent: Int)
    case batteryAbove(percent: Int)
    case isCharging
    case isNotCharging
    case screenSharing
    case notScreenSharing
    case timeOfDay(TimeOfDay)
    case duringWorkHours
    case outsideWorkHours
    
    func evaluate(context: ContextSnapshot) -> Bool {
        switch self {
        case .appIs(let bundleId):
            return context.currentApp?.bundleIdentifier == bundleId
            
        case .appCategory(let category):
            guard let app = context.currentApp else { return false }
            switch category {
            case .productivity: return app.isProductivity
            case .communication: return app.isCommunication
            case .entertainment: return app.isEntertainment
            case .any: return true
            }
            
        case .focusModeActive:
            return context.isFocusMode
            
        case .focusModeInactive:
            return !context.isFocusMode
            
        case .inMeeting:
            return context.isInMeeting
            
        case .notInMeeting:
            return !context.isInMeeting
            
        case .batteryBelow(let percent):
            return context.batteryLevel < percent
            
        case .batteryAbove(let percent):
            return context.batteryLevel > percent
            
        case .isCharging:
            return context.isCharging
            
        case .isNotCharging:
            return !context.isCharging
            
        case .screenSharing:
            return context.isScreenSharing
            
        case .notScreenSharing:
            return !context.isScreenSharing
            
        case .timeOfDay(let time):
            return context.timeOfDay == time
            
        case .duringWorkHours:
            return context.isWorkHours
            
        case .outsideWorkHours:
            return !context.isWorkHours
        }
    }
}

enum AppCategory: String, Codable {
    case productivity
    case communication
    case entertainment
    case any
}

// MARK: - Actions

enum ContextAction {
    case showWidget(widgetId: String)
    case hideWidget(widgetId: String)
    case setWidgetPriority(widgetId: String, priority: Int)
    case expandNotch
    case collapseNotch
    case showNotification(message: String)
    
    func execute(widgetManager: WidgetManager) {
        switch self {
        case .showWidget(let widgetId):
            if let uuid = UUID(uuidString: widgetId) {
                if let index = widgetManager.widgets.firstIndex(where: { $0.id == uuid }) {
                    widgetManager.widgets[index].isEnabled = true
                }
            }
            
        case .hideWidget(let widgetId):
            if let uuid = UUID(uuidString: widgetId) {
                if let index = widgetManager.widgets.firstIndex(where: { $0.id == uuid }) {
                    widgetManager.widgets[index].isEnabled = false
                }
            }
            
        case .setWidgetPriority(let widgetId, let priority):
            if let uuid = UUID(uuidString: widgetId),
               let index = widgetManager.widgets.firstIndex(where: { $0.id == uuid }) {
                widgetManager.widgets[index].priority = WidgetPriority(rawValue: priority) ?? .normal
            }
            
        case .expandNotch, .collapseNotch:
            // These would be handled by the NotchWindowController
            NotificationCenter.default.post(
                name: .contextActionNotification,
                object: self
            )
            
        case .showNotification(let message):
            // Show a macOS notification using modern UserNotifications
            let content = UNMutableNotificationContent()
            content.title = "Aura"
            content.body = message
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }
}

extension Notification.Name {
    static let contextActionNotification = Notification.Name("contextActionNotification")
}

// MARK: - Default Rules

extension ContextRule {
    /// Preset rules that come with the app
    static var defaultRules: [ContextRule] {
        [
            // Low battery: boost battery widget priority
            ContextRule(
                name: "Low Battery Alert",
                conditions: [.batteryBelow(percent: 20), .isNotCharging],
                actions: [.setWidgetPriority(widgetId: "battery", priority: 100)],
                priority: 90
            ),
            
            // In meeting: show calendar widget
            ContextRule(
                name: "Meeting Mode",
                conditions: [.inMeeting],
                actions: [.setWidgetPriority(widgetId: "calendar", priority: 80)],
                priority: 80
            ),
            
            // Screen sharing: minimize widgets
            ContextRule(
                name: "Presentation Mode",
                conditions: [.screenSharing],
                actions: [.collapseNotch],
                priority: 95
            ),
            
            // Focus mode: minimal UI
            ContextRule(
                name: "Focus Mode",
                conditions: [.focusModeActive],
                actions: [.collapseNotch],
                priority: 85
            )
        ]
    }
}
