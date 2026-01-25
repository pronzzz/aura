import Foundation
import IOKit.ps
import Combine

/// Detects battery level, charging status, and low power mode
class BatteryDetector: ObservableObject {
    @Published var level: Int = 100
    @Published var isCharging: Bool = false
    @Published var isLowPower: Bool = false
    @Published var timeRemaining: Int? // minutes
    
    private var timer: Timer?
    private var powerSourceObserver: CFRunLoopSource?
    
    func startMonitoring() {
        refresh()
        
        // Poll every minute
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        // Set up power source change callback
        setupPowerSourceObserver()
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        
        if let observer = powerSourceObserver {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), observer, .defaultMode)
        }
        powerSourceObserver = nil
    }
    
    func refresh() {
        updateBatteryInfo()
    }
    
    private func setupPowerSourceObserver() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        
        powerSourceObserver = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let detector = Unmanaged<BatteryDetector>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                detector.refresh()
            }
        }, context).takeRetainedValue()
        
        if let observer = powerSourceObserver {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), observer, .defaultMode)
        }
    }
    
    private func updateBatteryInfo() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return
        }
        
        // Battery level
        level = description[kIOPSCurrentCapacityKey as String] as? Int ?? 100
        
        // Charging status
        isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        
        // Low power mode (battery < 20% and not charging)
        isLowPower = level <= 20 && !isCharging
        
        // Time remaining
        if isCharging {
            if let time = description[kIOPSTimeToFullChargeKey as String] as? Int, time > 0 {
                timeRemaining = time
            } else {
                timeRemaining = nil
            }
        } else {
            if let time = description[kIOPSTimeToEmptyKey as String] as? Int, time > 0 {
                timeRemaining = time
            } else {
                timeRemaining = nil
            }
        }
    }
}
