import Combine
import Foundation
import IOKit.ps

/// Battery and power-adapter state, pushed by IOKit (no polling).
@MainActor
final class PowerService: ObservableObject {
    static let shared = PowerService()

    enum Event: Equatable {
        case pluggedIn, unplugged, low, full
    }

    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = true
    @Published private(set) var hasBattery = false
    /// Minutes to empty (on battery) or to full (charging), when macOS knows.
    @Published private(set) var minutesRemaining: Int?
    @Published private(set) var isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled

    let events = PassthroughSubject<Event, Never>()

    private var source: CFRunLoopSource?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        update(emitEvents: false)

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let loopSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let service = Unmanaged<PowerService>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { service.update(emitEvents: true) }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), loopSource, .defaultMode)
            source = loopSource
        }

        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            }
        }
    }

    var symbolName: String {
        if !hasBattery { return "powerplug.fill" }
        if isCharging || (isPluggedIn && level >= 100) { return "battery.100.bolt" }
        switch level {
        case ..<13: return "battery.0"
        case ..<38: return "battery.25"
        case ..<63: return "battery.50"
        case ..<88: return "battery.75"
        default: return "battery.100"
        }
    }

    var remainingDescription: String? {
        guard let minutes = minutesRemaining, minutes > 0 else { return nil }
        let text = minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
        return isPluggedIn ? "\(text) until full" : "\(text) left"
    }

    private func update(emitEvents: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return }

        var found = false
        var newLevel = level
        var newCharging = false
        var newPlugged = true
        var remaining: Int?

        for item in list {
            guard let info = IOPSGetPowerSourceDescription(snapshot, item)?.takeUnretainedValue() as? [String: Any],
                  (info[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            found = true
            let current = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = info[kIOPSMaxCapacityKey] as? Int ?? 100
            newLevel = maximum > 0 ? Int((Double(current) / Double(maximum) * 100).rounded()) : current
            newCharging = info[kIOPSIsChargingKey] as? Bool ?? false
            newPlugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let key = newPlugged ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            if let minutes = info[key] as? Int, minutes > 0 { remaining = minutes }
        }

        let oldLevel = level
        let oldPlugged = isPluggedIn

        hasBattery = found
        level = min(100, max(0, newLevel))
        isCharging = newCharging
        isPluggedIn = newPlugged
        minutesRemaining = remaining

        guard emitEvents, found else { return }
        if newPlugged && !oldPlugged { events.send(.pluggedIn) }
        if !newPlugged && oldPlugged { events.send(.unplugged) }
        let threshold = Pref.int(.lowBatteryThreshold)
        if !newPlugged, level <= threshold, oldLevel > threshold { events.send(.low) }
        if newPlugged, level >= 100, oldLevel < 100 { events.send(.full) }
    }
}
