import AppKit
import Combine
import EventKit

struct CalendarEvent: Identifiable, Equatable {
    let id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var color: NSColor
    var location: String?
    var meetingURL: URL?

    var isHappeningNow: Bool { start <= Date() && end > Date() }

    var timeDescription: String {
        if isAllDay { return "All day" }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: start)
    }

    var relativeDescription: String {
        if isHappeningNow { return "Now" }
        let minutes = Int(start.timeIntervalSinceNow / 60)
        if minutes < 1 { return "Starting" }
        if minutes < 60 { return "in \(minutes)m" }
        return timeDescription
    }
}

/// Upcoming events from all calendars (today and tomorrow), with meeting-link detection.
@MainActor
final class CalendarService: ObservableObject {
    static let shared = CalendarService()

    @Published private(set) var events: [CalendarEvent] = []
    @Published private(set) var status = EKEventStore.authorizationStatus(for: .event)

    private let store = EKEventStore()
    private var refreshTimer: Timer?
    private var started = false

    private init() {}

    var isAuthorized: Bool {
        status == .fullAccess
    }

    var nextEvent: CalendarEvent? {
        events.first { !$0.isAllDay && $0.end > Date() }
    }

    func start() {
        guard !started else { return }
        started = true
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        reload()
    }

    func requestAccess() async {
        _ = try? await store.requestFullAccessToEvents()
        status = EKEventStore.authorizationStatus(for: .event)
        reload()
    }

    func reload() {
        status = EKEventStore.authorizationStatus(for: .event)
        guard isAuthorized else { events = []; return }

        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 2, to: start) else { return }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let now = Date()

        events = store.events(matching: predicate)
            .filter { $0.endDate > now }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay { return !lhs.isAllDay }
                return lhs.startDate < rhs.startDate
            }
            .prefix(20)
            .map { event in
                CalendarEvent(id: event.eventIdentifier ?? UUID().uuidString,
                              title: event.title ?? "Untitled",
                              start: event.startDate,
                              end: event.endDate,
                              isAllDay: event.isAllDay,
                              color: event.calendar.map { NSColor(cgColor: $0.cgColor) ?? .systemBlue } ?? .systemBlue,
                              location: event.location,
                              meetingURL: Self.meetingURL(in: event))
            }
    }

    func openCalendarApp() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
        }
    }

    func applyDemo(_ events: [CalendarEvent]) {
        status = .fullAccess
        self.events = events
    }

    private static let meetingPattern = try? NSRegularExpression(
        pattern: #"https://[A-Za-z0-9.-]*(zoom\.us|meet\.google\.com|teams\.microsoft\.com|teams\.live\.com|webex\.com|whereby\.com|facetime\.apple\.com|around\.co|meet\.jit\.si)/[^\s<>"']*"#,
        options: [.caseInsensitive])

    private static func meetingURL(in event: EKEvent) -> URL? {
        let haystacks = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in haystacks {
            let range = NSRange(text.startIndex..., in: text)
            if let match = meetingPattern?.firstMatch(in: text, range: range),
               let swiftRange = Range(match.range, in: text) {
                return URL(string: String(text[swiftRange]))
            }
        }
        return nil
    }
}
