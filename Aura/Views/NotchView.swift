import SwiftUI

/// Main SwiftUI view that renders the notch interface
struct NotchView: View {
    @ObservedObject var viewModel: NotchViewModel
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        ZStack {
            // Background shape
            NotchShape(cornerRadius: viewModel.isExpanded ? 20 : 12)
                .fill(backgroundColor)
                .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Drop zone overlay
            NotchDropZone()
            
            // Content
            VStack(spacing: 8) {
                if viewModel.isExpanded {
                    expandedContent
                } else {
                    collapsedContent
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: viewModel.isExpanded)
    }
    
    // MARK: - Background Color
    
    private var backgroundColor: Color {
        themeManager.isDarkMode ? Color.black.opacity(0.85) : Color.white.opacity(0.9)
    }
    
    // MARK: - Collapsed View (minimal widgets)
    
    private var collapsedContent: some View {
        HStack(spacing: 12) {
            // Clock
            Text(timeString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(themeManager.textColor)
            
            Spacer()
            
            // Battery indicator
            BatteryIndicator(compact: true)
                .foregroundColor(themeManager.textColor)
        }
    }
    
    // MARK: - Expanded View (full widgets)
    
    private var expandedContent: some View {
        VStack(spacing: 12) {
            // Top row - Time and Date
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 24, weight: .semibold, design: .rounded))
                    Text(dateString)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
                
                Spacer()
                
                // Battery with percentage
                BatteryIndicator(compact: false)
            }
            .foregroundColor(themeManager.textColor)
            
            Divider()
                .background(themeManager.dividerColor)
            
            // Temporary clipboard if has items
            TemporaryClipboardView()
            
            // Widget area - use real widgets
            WidgetContainer(isExpanded: true)
        }
    }
    
    // MARK: - Time/Date Helpers
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: Date())
    }
    
    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}

// MARK: - Battery Indicator

struct BatteryIndicator: View {
    let compact: Bool
    @State private var batteryLevel: Int = 100
    @State private var isCharging: Bool = false
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: batteryIcon)
                .font(.system(size: compact ? 12 : 16))
            
            if !compact {
                Text("\(batteryLevel)%")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .onAppear {
            updateBatteryStatus()
        }
    }
    
    private var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        switch batteryLevel {
        case 0..<25: return "battery.25"
        case 25..<50: return "battery.50"
        case 50..<75: return "battery.75"
        default: return "battery.100"
        }
    }
    
    private func updateBatteryStatus() {
        // Get actual battery level using IOKit
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
           let source = sources.first,
           let description = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] {
            
            batteryLevel = description[kIOPSCurrentCapacityKey as String] as? Int ?? 100
            isCharging = description[kIOPSIsChargingKey as String] as? Bool ?? false
        }
    }
}

// MARK: - Widget Placeholder

struct WidgetPlaceholder: View {
    let icon: String
    let label: String
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 20))
            Text(label)
                .font(.system(size: 10))
        }
        .foregroundColor(themeManager.secondaryTextColor)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(themeManager.widgetBackground)
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    NotchView(viewModel: NotchViewModel())
        .frame(width: 340, height: 160)
        .background(Color.gray.opacity(0.2))
}
