import SwiftUI
import CoreWLAN
import SystemConfiguration

/// WiFi widget showing network connection status
class WiFiWidget: AuraWidget {
    let id = UUID()
    let name = "Wi-Fi"
    let iconName = "wifi"
    
    @Published var size: WidgetSize = .small
    @Published var priority: WidgetPriority = .normal
    @Published var isEnabled: Bool = true
    
    @Published private(set) var isConnected: Bool = false
    @Published private(set) var networkName: String?
    @Published private(set) var signalStrength: Int = 0
    
    private var timer: Timer?
    
    func body(for size: WidgetSize) -> some View {
        WiFiWidgetView(
            isConnected: isConnected,
            networkName: networkName,
            signalStrength: signalStrength,
            size: size
        )
    }
    
    func onAppear() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        updateWiFiInfo()
    }
    
    private func updateWiFiInfo() {
        guard let interface = CWWiFiClient.shared().interface() else {
            isConnected = false
            networkName = nil
            signalStrength = 0
            return
        }
        
        isConnected = interface.ssid() != nil
        networkName = interface.ssid()
        signalStrength = interface.rssiValue()
    }
}

struct WiFiWidgetView: View {
    let isConnected: Bool
    let networkName: String?
    let signalStrength: Int
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Image(systemName: wifiIcon)
                    .font(.system(size: 14))
            case .medium:
                VStack(spacing: 2) {
                    Image(systemName: wifiIcon)
                        .font(.system(size: 16))
                    Text(isConnected ? "On" : "Off")
                        .font(.system(size: 9))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                HStack(spacing: 8) {
                    Image(systemName: wifiIcon)
                        .font(.system(size: 20))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(networkName ?? "Not Connected")
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                        Text(signalDescription)
                            .font(.system(size: 10))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WidgetBackground())
            }
        }
        .foregroundColor(isConnected ? themeManager.textColor : themeManager.secondaryTextColor)
    }
    
    private var wifiIcon: String {
        guard isConnected else { return "wifi.slash" }
        
        // RSSI ranges: -30 (excellent) to -90 (poor)
        switch signalStrength {
        case (-50)...0: return "wifi"
        case (-60)..<(-50): return "wifi"
        case (-70)..<(-60): return "wifi"
        default: return "wifi.exclamationmark"
        }
    }
    
    private var signalDescription: String {
        guard isConnected else { return "Disconnected" }
        
        switch signalStrength {
        case (-50)...0: return "Excellent Signal"
        case (-60)..<(-50): return "Good Signal"
        case (-70)..<(-60): return "Fair Signal"
        default: return "Weak Signal"
        }
    }
}
