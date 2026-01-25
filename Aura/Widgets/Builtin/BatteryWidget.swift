import SwiftUI
import IOKit.ps

/// Battery widget showing charge level and status
class BatteryWidget: AuraWidget {
    let id = UUID()
    let name = "Battery"
    let iconName = "battery.100"
    
    @Published var size: WidgetSize = .small
    @Published var priority: WidgetPriority = .normal
    @Published var isEnabled: Bool = true
    
    @Published private(set) var level: Int = 100
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var timeRemaining: String?
    
    private var timer: Timer?
    
    func body(for size: WidgetSize) -> some View {
        BatteryWidgetView(level: level, isCharging: isCharging, timeRemaining: timeRemaining, size: size)
    }
    
    func onAppear() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        updateBatteryInfo()
    }
    
    private func updateBatteryInfo() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return
        }
        
        level = description[kIOPSCurrentCapacityKey as String] as? Int ?? 100
        isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        
        if let timeToEmpty = description[kIOPSTimeToEmptyKey as String] as? Int, timeToEmpty > 0 {
            let hours = timeToEmpty / 60
            let minutes = timeToEmpty % 60
            timeRemaining = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        } else if let timeToFull = description[kIOPSTimeToFullChargeKey as String] as? Int, timeToFull > 0 {
            let hours = timeToFull / 60
            let minutes = timeToFull % 60
            timeRemaining = hours > 0 ? "\(hours)h \(minutes)m until full" : "\(minutes)m until full"
        } else {
            timeRemaining = nil
        }
        
        // Update priority based on battery level
        if level <= 10 {
            priority = .critical
        } else if level <= 20 {
            priority = .high
        } else {
            priority = .normal
        }
    }
}

struct BatteryWidgetView: View {
    let level: Int
    let isCharging: Bool
    let timeRemaining: String?
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Image(systemName: batteryIcon)
                    .font(.system(size: 14))
            case .medium:
                VStack(spacing: 2) {
                    Image(systemName: batteryIcon)
                        .font(.system(size: 16))
                    Text("\(level)%")
                        .font(.system(size: 9))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                HStack(spacing: 8) {
                    BatteryGauge(level: level, isCharging: isCharging)
                        .frame(width: 40, height: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(level)%")
                            .font(.system(size: 14, weight: .semibold))
                        if let time = timeRemaining {
                            Text(time)
                                .font(.system(size: 10))
                                .foregroundColor(themeManager.secondaryTextColor)
                        } else {
                            Text(isCharging ? "Charging" : "On Battery")
                                .font(.system(size: 10))
                                .foregroundColor(themeManager.secondaryTextColor)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WidgetBackground())
            }
        }
        .foregroundColor(batteryColor)
    }
    
    private var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch level {
        case 0..<10: return "battery.0"
        case 10..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private var batteryColor: Color {
        if isCharging {
            return .green
        }
        switch level {
        case 0..<10: return .red
        case 10..<20: return .orange
        default: return themeManager.textColor
        }
    }
}

// Custom battery gauge view for expanded mode
struct BatteryGauge: View {
    let level: Int
    let isCharging: Bool
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Battery outline
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                
                // Battery fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(fillColor)
                    .frame(width: max(0, geometry.size.width * CGFloat(level) / 100 - 4))
                    .padding(2)
                
                // Charging bolt
                if isCharging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    private var fillColor: Color {
        switch level {
        case 0..<10: return .red
        case 10..<20: return .orange
        default: return .green
        }
    }
}
