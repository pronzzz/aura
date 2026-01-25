import Foundation
import Combine

/// Detects Focus Mode / Do Not Disturb status
class FocusModeDetector: ObservableObject {
    @Published var isFocusMode: Bool = false
    @Published var focusModeName: String?
    
    private var timer: Timer?
    private var distributedObserver: NSObjectProtocol?
    
    func startMonitoring() {
        refresh()
        
        // Poll periodically (Focus Mode doesn't have a public notification)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        
        // Listen for system configuration changes
        distributedObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.donotdisturb.stateChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        
        if let observer = distributedObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        distributedObserver = nil
    }
    
    func refresh() {
        // Check Focus Mode using UserDefaults (requires permission in newer macOS)
        // This is a workaround as Focus Mode API is private
        checkFocusMode()
    }
    
    private func checkFocusMode() {
        // Method 1: Check DND via Notification Center preferences
        if let dndPrefs = UserDefaults(suiteName: "com.apple.notificationcenterui") {
            let dndEnabled = dndPrefs.bool(forKey: "doNotDisturb")
            isFocusMode = dndEnabled
            if dndEnabled {
                focusModeName = "Do Not Disturb"
            } else {
                focusModeName = nil
            }
            return
        }
        
        // Method 2: Check Focus status via distributed notification payload
        // (Limited but works without special permissions)
        let focusPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        
        if FileManager.default.fileExists(atPath: focusPath.path) {
            do {
                let data = try Data(contentsOf: focusPath)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let assertions = json["data"] as? [[String: Any]],
                   !assertions.isEmpty {
                    isFocusMode = true
                    // Try to extract focus mode name
                    if let storeData = assertions.first?["storeData"] as? [String: Any],
                       let modeName = storeData["focusModeName"] as? String {
                        focusModeName = modeName
                    } else {
                        focusModeName = "Focus"
                    }
                    return
                }
            } catch {
                // Silently fail - file might not be accessible
            }
        }
        
        isFocusMode = false
        focusModeName = nil
    }
}
