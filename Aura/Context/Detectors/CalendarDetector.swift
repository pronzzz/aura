import Foundation
import EventKit
import Combine

/// Detects upcoming calendar events and meeting status
class CalendarDetector: ObservableObject {
    @Published var upcomingMeeting: EKEvent?
    @Published var isInMeeting: Bool = false
    @Published var hasAccess: Bool = false
    
    private let eventStore = EKEventStore()
    private var timer: Timer?
    
    func startMonitoring() {
        requestAccess()
        
        // Refresh every 5 minutes
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        // Listen for calendar changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(calendarChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        NotificationCenter.default.removeObserver(self)
    }
    
    func refresh() {
        guard hasAccess else { return }
        fetchUpcomingMeeting()
    }
    
    @objc private func calendarChanged() {
        refresh()
    }
    
    private func requestAccess() {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchUpcomingMeeting()
                    }
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { [weak self] granted, error in
                DispatchQueue.main.async {
                    self?.hasAccess = granted
                    if granted {
                        self?.fetchUpcomingMeeting()
                    }
                }
            }
        }
    }
    
    private func fetchUpcomingMeeting() {
        let now = Date()
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
        
        // Check if we're currently in a meeting
        if let currentMeeting = events.first(where: { event in
            now >= event.startDate && now <= event.endDate
        }) {
            isInMeeting = true
            upcomingMeeting = currentMeeting
        } else {
            isInMeeting = false
            // Get next upcoming meeting
            upcomingMeeting = events.first { $0.startDate > now }
        }
    }
}
