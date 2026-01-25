import Foundation
import AppKit

/// Handles parsing natural language into structured commands
class CommandParser {
    
    /// Intent categories for commands
    enum CommandIntent {
        case showWidget(name: String)
        case hideWidget(name: String)
        case toggleWidget(name: String)
        case expandNotch
        case collapseNotch
        case toggleFocus
        case openApp(name: String)
        case systemPreference(name: String)
        case unknown(query: String)
    }
    
    /// Parse natural language input without AI (rule-based fallback)
    static func parse(_ input: String) -> CommandIntent {
        let lowercased = input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Widget commands
        if lowercased.contains("show") {
            if let widget = extractWidget(from: lowercased) {
                return .showWidget(name: widget)
            }
        }
        
        if lowercased.contains("hide") {
            if let widget = extractWidget(from: lowercased) {
                return .hideWidget(name: widget)
            }
        }
        
        if lowercased.contains("toggle") {
            if let widget = extractWidget(from: lowercased) {
                return .toggleWidget(name: widget)
            }
        }
        
        // Notch commands
        if lowercased.contains("expand") || lowercased.contains("open aura") {
            return .expandNotch
        }
        
        if lowercased.contains("collapse") || lowercased.contains("minimize") || lowercased.contains("close aura") {
            return .collapseNotch
        }
        
        // Focus mode
        if lowercased.contains("focus") || lowercased.contains("do not disturb") || lowercased.contains("dnd") {
            return .toggleFocus
        }
        
        // Open app
        if lowercased.starts(with: "open ") {
            let appName = String(lowercased.dropFirst(5))
            return .openApp(name: appName)
        }
        
        // Settings/preferences
        if lowercased.contains("settings") || lowercased.contains("preferences") {
            if lowercased.contains("display") || lowercased.contains("brightness") {
                return .systemPreference(name: "Displays")
            }
            if lowercased.contains("sound") || lowercased.contains("volume") {
                return .systemPreference(name: "Sound")
            }
            if lowercased.contains("bluetooth") {
                return .systemPreference(name: "Bluetooth")
            }
            if lowercased.contains("wifi") || lowercased.contains("network") {
                return .systemPreference(name: "Network")
            }
            return .systemPreference(name: "General")
        }
        
        return .unknown(query: input)
    }
    
    /// Extract widget name from command
    private static func extractWidget(from input: String) -> String? {
        let widgetKeywords = [
            "clock": "Clock",
            "time": "Clock",
            "battery": "Battery",
            "power": "Battery",
            "wifi": "WiFi",
            "network": "WiFi",
            "internet": "WiFi",
            "music": "Music",
            "player": "Music",
            "now playing": "Music",
            "calendar": "Calendar",
            "events": "Calendar",
            "meeting": "Calendar",
            "system": "System",
            "cpu": "System",
            "memory": "System",
            "stats": "System"
        ]
        
        for (keyword, widgetName) in widgetKeywords {
            if input.contains(keyword) {
                return widgetName
            }
        }
        
        return nil
    }
    
    /// Execute a parsed command
    static func execute(_ intent: CommandIntent, widgetManager: WidgetManager) {
        switch intent {
        case .showWidget(let name):
            if let widget = widgetManager.widgets.first(where: { 
                $0.name.lowercased() == name.lowercased() 
            }) {
                if let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].isEnabled = true
                }
            }
            
        case .hideWidget(let name):
            if let widget = widgetManager.widgets.first(where: { 
                $0.name.lowercased() == name.lowercased() 
            }) {
                if let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].isEnabled = false
                }
            }
            
        case .toggleWidget(let name):
            if let widget = widgetManager.widgets.first(where: { 
                $0.name.lowercased() == name.lowercased() 
            }) {
                if let index = widgetManager.widgets.firstIndex(where: { $0.id == widget.id }) {
                    widgetManager.widgets[index].isEnabled.toggle()
                }
            }
            
        case .expandNotch, .collapseNotch:
            NotificationCenter.default.post(
                name: .contextActionNotification,
                object: intent
            )
            
        case .toggleFocus:
            // Toggle Focus Mode using AppleScript
            let script = """
            tell application "System Events"
                tell process "Control Center"
                    -- Trigger Focus via menu bar
                end tell
            end tell
            """
            if let appleScript = NSAppleScript(source: script) {
                var error: NSDictionary?
                appleScript.executeAndReturnError(&error)
            }
            
        case .openApp(let name):
            NSWorkspace.shared.launchApplication(name.capitalized)
            
        case .systemPreference(let name):
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.\(name)")!
            NSWorkspace.shared.open(url)
            
        case .unknown:
            break
        }
    }
}
