import AppKit
import Combine
import SwiftUI

/// Decides which live activity the closed notch shows and fires Quick Peeks.
///
/// Priority: running timer → just plugged in → low battery → music.
@MainActor
final class ActivityCenter: ObservableObject {
    static let shared = ActivityCenter()

    @Published private(set) var current: LiveActivityKind?
    @Published private(set) var peek: Peek?

    private var chargingUntil = Date.distantPast
    private var lowBatteryUntil = Date.distantPast
    private var peekWork: DispatchWorkItem?
    private var ticker: Timer?
    private var peekedMeetings = Set<String>()
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        let media = NowPlayingService.shared
        media.$isPlaying.combineLatest(media.$track)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.recompute() } }
            .store(in: &cancellables)

        media.trackChanged
            .sink { [weak self] track in
                guard Pref.bool(.peekOnSongChange) else { return }
                // Let the artwork load before peeking.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    let media = NowPlayingService.shared
                    guard media.track == track else { return }
                    self?.showPeek(Peek(kind: .music, title: track.title, subtitle: track.artist,
                                        icon: "music.note", tint: Color(nsColor: media.accent),
                                        artwork: media.artwork))
                }
            }
            .store(in: &cancellables)

        TimerService.shared.$timers
            .sink { [weak self] _ in DispatchQueue.main.async { self?.recompute() } }
            .store(in: &cancellables)

        PowerService.shared.events
            .sink { [weak self] event in self?.handle(event) }
            .store(in: &cancellables)

        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.recompute()
                self?.checkMeetings()
            }
        }
        recompute()
    }

    func showPeek(_ newPeek: Peek, duration: TimeInterval = 3.2) {
        guard Pref.bool(.quickPeekEnabled) else { return }
        peekWork?.cancel()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { peek = newPeek }
        let work = DispatchWorkItem { [weak self] in
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) { self?.peek = nil }
        }
        peekWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func dismissPeek() {
        peekWork?.cancel()
        peek = nil
    }

    /// Used by the snapshot renderer.
    func applyDemo(current: LiveActivityKind?, peek: Peek?) {
        self.current = current
        self.peek = peek
    }

    private func handle(_ event: PowerService.Event) {
        let power = PowerService.shared
        let linger = max(3, Pref.double(.activityLinger))
        switch event {
        case .pluggedIn:
            chargingUntil = Date().addingTimeInterval(linger)
            if Pref.bool(.peekOnPower) {
                showPeek(Peek(kind: .power, title: "Charging", subtitle: "\(power.level)%" + (power.remainingDescription.map { " · \($0)" } ?? ""),
                              icon: "bolt.fill", tint: .green))
            }
        case .unplugged:
            if Pref.bool(.peekOnPower) {
                showPeek(Peek(kind: .power, title: "On Battery", subtitle: "\(power.level)%" + (power.remainingDescription.map { " · \($0)" } ?? ""),
                              icon: power.symbolName, tint: .white))
            }
        case .low:
            lowBatteryUntil = Date().addingTimeInterval(linger * 2)
            showPeek(Peek(kind: .power, title: "Low Battery", subtitle: "\(power.level)% remaining",
                          icon: "battery.25", tint: .red), duration: 5)
        case .full:
            if Pref.bool(.peekOnPower) {
                showPeek(Peek(kind: .power, title: "Fully Charged", subtitle: "100%", icon: "battery.100.bolt", tint: .green))
            }
        }
        recompute()
    }

    private func recompute() {
        let now = Date()
        var next: LiveActivityKind?
        if Pref.bool(.timerActivity), TimerService.shared.hasRunning {
            next = .timer
        } else if Pref.bool(.batteryActivity), now < chargingUntil {
            next = .charging
        } else if Pref.bool(.batteryActivity), now < lowBatteryUntil {
            next = .lowBattery
        } else if Pref.bool(.musicActivity), NowPlayingService.shared.isActive {
            next = .music
        }
        if next != current {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { current = next }
        }
    }

    private func checkMeetings() {
        guard Pref.bool(.peekOnMeetings), let event = CalendarService.shared.nextEvent else { return }
        let lead = TimeInterval(max(1, Pref.int(.meetingPeekMinutes)) * 60)
        let untilStart = event.start.timeIntervalSinceNow
        guard untilStart > 0, untilStart <= lead, !peekedMeetings.contains(event.id) else { return }
        peekedMeetings.insert(event.id)
        let minutes = max(1, Int((untilStart / 60).rounded()))
        showPeek(Peek(kind: .meeting, title: event.title,
                      subtitle: "Starts in \(minutes) min" + (event.meetingURL != nil ? " · Join from the notch" : ""),
                      icon: "calendar", tint: Color(nsColor: event.color)), duration: 6)
    }
}
