import SwiftUI
import Combine

/// Clock widget showing current time
class ClockWidget: AuraWidget {
    let id = UUID()
    let name = "Clock"
    let iconName = "clock"
    
    @Published var size: WidgetSize = .small
    @Published var priority: WidgetPriority = .normal
    @Published var isEnabled: Bool = true
    
    @Published private var currentTime = Date()
    private var timer: Timer?
    
    func body(for size: WidgetSize) -> some View {
        ClockWidgetView(time: currentTime, size: size)
    }
    
    func onAppear() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.currentTime = Date()
        }
    }
    
    func onDisappear() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        currentTime = Date()
    }
}

struct ClockWidgetView: View {
    let time: Date
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                Text(timeString)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
            case .medium:
                VStack(spacing: 2) {
                    Text(timeString)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(shortDateString)
                        .font(.system(size: 9))
                        .foregroundColor(themeManager.secondaryTextColor)
                }
            case .expanded:
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeString)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                        Text(fullDateString)
                            .font(.system(size: 11))
                            .foregroundColor(themeManager.secondaryTextColor)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(WidgetBackground())
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: time)
    }
    
    private var shortDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: time)
    }
    
    private var fullDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d"
        return formatter.string(from: time)
    }
}
