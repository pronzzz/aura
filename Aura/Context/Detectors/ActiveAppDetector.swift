import Foundation
import AppKit
import Combine

/// Detects the currently active/frontmost application
class ActiveAppDetector: ObservableObject {
    @Published var currentApp: RunningApp?
    
    private var observer: NSObjectProtocol?
    
    func startMonitoring() {
        // Get initial app
        refresh()
        
        // Listen for app activation changes
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleAppChange(notification)
        }
    }
    
    func stopMonitoring() {
        if let observer = observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observer = nil
    }
    
    func refresh() {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            currentApp = nil
            return
        }
        
        currentApp = RunningApp(
            bundleIdentifier: frontApp.bundleIdentifier ?? "",
            name: frontApp.localizedName ?? "Unknown",
            icon: frontApp.icon
        )
    }
    
    private func handleAppChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }
        
        currentApp = RunningApp(
            bundleIdentifier: app.bundleIdentifier ?? "",
            name: app.localizedName ?? "Unknown",
            icon: app.icon
        )
    }
}
