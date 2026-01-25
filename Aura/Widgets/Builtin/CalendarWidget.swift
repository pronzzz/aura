import SwiftUI
import EventKit

/// Calendar widget showing upcoming events
class CalendarWidget: AuraWidget {
    let id = UUID()
    let name = "Calendar"
    let iconName = "calendar"
    
    @Published var size: WidgetSize = .medium
    @Published var priority: WidgetPriority = .normal
    @Published var isEnabled: Bool = false // Disabled by default, requires permission
    
    @Published private(set) var nextEvent: EKEvent?
    @Published private(set) var hasAccess: Bool = false
    
    private let eventStore = EKEventStore()
    private var timer: Timer?
    
    func body(for size: WidgetSize) -> some View {
        CalendarWidgetView(nextEvent: nextEvent, hasAccess: hasAccess, size: size)
    }
    
    func onAppear() {
        requestAccess()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        guard hasAccess else { return }
        fetchNextEvent()
    }
    
    private func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchNextEvent()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchNextEvent()
                    }
                }
            }
        }
    }
    
    private func fetchNextEvent() {
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        
        nextEvent = events.first
        
        // Update priority based on event proximity
        if let event = nextEvent {
            let minutesUntil = Calendar.current.dateComponents([.minute], from: now, to: event.startDate).minute ?? 0
            if minutesUntil <= 5 {
                priority = .critical
            } else if minutesUntil <= 15 {
                priority = .high
            } else {
                priority = .normal
            }
        } else {
            priority = .low
        }
    }
}

struct CalendarWidgetView: View {
    let nextEvent: EKEvent?
    let hasAccess: Bool
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Image(systemName: nextEvent != nil ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 14))
            case .medium:
                VStack(spacing: 2) {
                    Image(systemName: "calendar")
                        .font(.system(size: 16))
                    Text(shortEventText)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var shortEventText: String {
        guard hasAccess else { return "No Access" }
        guard let event = nextEvent else { return "No Events" }
        return timeUntilEvent(event)
    }
    
    private var expandedView: some View {
        HStack(spacing: 8) {
            // Calendar color indicator
            RoundedRectangle(cornerRadius: 4)
                .fill(calendarColor)
                .frame(width: 4, height: 40)
            
            VStack(alignment: .leading, spacing: 2) {
                if !hasAccess {
                    Text("Calendar Access Required")
                        .font(.system(size: 12, weight: .medium))
                    Text("Grant access in Settings")
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.secondaryTextColor)
                } else if let event = nextEvent {
                    Text(event.title ?? "Untitled Event")
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(eventTimeString(event))
                        Text("•")
                        Text(timeUntilEvent(event))
                    }
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.secondaryTextColor)
                } else {
                    Text("No Upcoming Events")
                        .font(.system(size: 12, weight: .medium))
                    Text("Enjoy your free time!")
                        .font(.system(size: 10))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WidgetBackground())
    }
    
    private var calendarColor: Color {
        guard let event = nextEvent, let cgColor = event.calendar.cgColor else {
            return .blue
        }
        return Color(cgColor: cgColor)
    }
    
    private func eventTimeString(_ event: EKEvent) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: event.startDate)
    }
    
    private func timeUntilEvent(_ event: EKEvent) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents([.hour, .minute], from: now, to: event.startDate)
        
        if let hours = components.hour, hours > 0 {
            return "in \(hours)h \(components.minute ?? 0)m"
        } else if let minutes = components.minute, minutes > 0 {
            return "in \(minutes)m"
        } else {
            return "Now"
        }
    }
}
