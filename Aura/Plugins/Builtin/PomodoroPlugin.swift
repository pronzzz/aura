import Foundation
import SwiftUI
import UserNotifications

/// Pomodoro timer plugin with work/break intervals
class PomodoroPlugin: BasePlugin {
    @Published var isRunning: Bool = false
    @Published var isWorkPhase: Bool = true
    @Published var timeRemaining: Int = 25 * 60  // 25 minutes
    @Published var completedPomodoros: Int = 0
    
    private var timer: Timer?
    private let workDuration = 25 * 60  // 25 minutes
    private let shortBreakDuration = 5 * 60  // 5 minutes
    private let longBreakDuration = 15 * 60  // 15 minutes
    
    override func widgetView(size: WidgetSize) -> AnyView {
        AnyView(PomodoroWidgetView(plugin: self, size: size))
    }
    
    override func handleCommand(_ command: String) async -> String? {
        let lowercased = command.lowercased()
        
        if lowercased.contains("start") && lowercased.contains("pomodoro") {
            await MainActor.run { startTimer() }
            return "Started Pomodoro timer"
        }
        
        if lowercased.contains("stop") && lowercased.contains("pomodoro") {
            await MainActor.run { stopTimer() }
            return "Stopped Pomodoro timer"
        }
        
        if lowercased.contains("pomodoro") && lowercased.contains("status") {
            let phase = isWorkPhase ? "work" : "break"
            let mins = timeRemaining / 60
            return "Pomodoro: \(mins) min left in \(phase) phase. \(completedPomodoros) completed today."
        }
        
        return nil
    }
    
    func startTimer() {
        isRunning = true
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }
    
    func stopTimer() {
        isRunning = false
        timer?.invalidate()
        timer = nil
    }
    
    func resetTimer() {
        stopTimer()
        isWorkPhase = true
        timeRemaining = workDuration
    }
    
    private func tick() {
        if timeRemaining > 0 {
            timeRemaining -= 1
        } else {
            // Phase complete
            if isWorkPhase {
                completedPomodoros += 1
                showNotification(title: "Pomodoro Complete!", body: "Time for a break")
                
                // Long break every 4 pomodoros
                timeRemaining = completedPomodoros % 4 == 0 ? longBreakDuration : shortBreakDuration
            } else {
                showNotification(title: "Break Over", body: "Ready to focus?")
                timeRemaining = workDuration
            }
            
            isWorkPhase.toggle()
        }
    }
    
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

struct PomodoroWidgetView: View {
    @ObservedObject var plugin: PomodoroPlugin
    let size: WidgetSize
    @StateObject private var themeManager = ThemeManager.shared
    
    var body: some View {
        Group {
            switch size {
            case .small:
                compactView
            case .medium:
                mediumView
            case .expanded:
                expandedView
            }
        }
        .foregroundColor(themeManager.textColor)
    }
    
    private var compactView: some View {
        HStack(spacing: 4) {
            Image(systemName: plugin.isWorkPhase ? "brain.head.profile" : "cup.and.saucer.fill")
                .foregroundColor(plugin.isWorkPhase ? .red : .green)
            Text(timeString)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
        }
    }
    
    private var mediumView: some View {
        VStack(spacing: 4) {
            Image(systemName: plugin.isWorkPhase ? "brain.head.profile" : "cup.and.saucer.fill")
                .foregroundColor(plugin.isWorkPhase ? .red : .green)
            Text(timeString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
            Text(plugin.isWorkPhase ? "Focus" : "Break")
                .font(.system(size: 10))
                .foregroundColor(themeManager.secondaryTextColor)
        }
    }
    
    private var expandedView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(plugin.isWorkPhase ? "Focus Time" : "Break Time")
                    .font(.headline)
                Text(timeString)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                Text("\(plugin.completedPomodoros) pomodoros today")
                    .font(.caption)
                    .foregroundColor(themeManager.secondaryTextColor)
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button(action: { plugin.isRunning ? plugin.stopTimer() : plugin.startTimer() }) {
                    Image(systemName: plugin.isRunning ? "pause.fill" : "play.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                
                Button(action: { plugin.resetTimer() }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
    }
    
    private var timeString: String {
        let mins = plugin.timeRemaining / 60
        let secs = plugin.timeRemaining % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
