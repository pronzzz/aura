import Foundation
import Combine
import AppKit

/// Detects screen sharing and screen recording status
class ScreenShareDetector: ObservableObject {
    @Published var isSharing: Bool = false
    @Published var isRecording: Bool = false
    
    private var timer: Timer?
    
    func startMonitoring() {
        refresh()
        
        // Poll every 5 seconds (screen share state can change quickly)
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }
    
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }
    
    func refresh() {
        checkScreenSharingStatus()
    }
    
    private func checkScreenSharingStatus() {
        // Method 1: Check for common screen sharing apps
        let screenShareApps = [
            "com.apple.screensharing",
            "us.zoom.xos",
            "com.microsoft.teams",
            "com.google.Chrome",  // Can be doing screen share
            "com.tinyspeck.slackmacgap",
            "com.webex.meetingmanager",
            "com.cisco.webexmeetingsapp"
        ]
        
        let runningApps = NSWorkspace.shared.runningApplications
        let activeScreenShareApps = runningApps.filter { app in
            guard let bundleId = app.bundleIdentifier else { return false }
            return screenShareApps.contains(bundleId)
        }
        
        // Method 2: Check for screen capture permission being actively used
        // This uses CGWindowListCopyWindowInfo to detect if recording software is active
        if let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
            
            // Check for windows from known recording apps
            let recordingApps = [
                "QuickTime Player",
                "Screen Recording",
                "OBS",
                "Loom",
                "CleanShot X",
                "Kap"
            ]
            
            for window in windowList {
                if let ownerName = window[kCGWindowOwnerName as String] as? String {
                    if recordingApps.contains(where: { ownerName.contains($0) }) {
                        isRecording = true
                        break
                    }
                }
            }
        }
        
        // Method 3: Check if SharePlay or other system sharing is active
        // Using distributed notification center for Zoom/Teams status
        checkMeetingAppStatus()
        
        // If any video conferencing app is running, consider potential sharing
        isSharing = !activeScreenShareApps.isEmpty
    }
    
    private func checkMeetingAppStatus() {
        // Check Zoom status if available
        if let zoomDefaults = UserDefaults(suiteName: "us.zoom.xos") {
            let inMeeting = zoomDefaults.bool(forKey: "in_meeting")
            if inMeeting {
                isSharing = true
            }
        }
        
        // Check for active video calls via audio device usage
        // This is a heuristic - if Zoom audio device is active, likely in call
        let task = Process()
        task.launchPath = "/usr/bin/pmset"
        task.arguments = ["-g", "assertions"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Check for display sleep prevention (common during screen sharing)
                if output.contains("PreventUserIdleDisplaySleep") {
                    // Something is preventing display sleep - could be video call
                    // But don't set isSharing here as it could be other things
                }
            }
        } catch {
            // Silently fail
        }
    }
}
