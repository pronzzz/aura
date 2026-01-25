import Foundation
import SwiftUI

/// Plugin manifest defines plugin metadata and requirements
struct PluginManifest: Codable {
    let id: String
    let name: String
    let version: String
    let author: String
    let description: String
    let minAuraVersion: String
    let permissions: [PluginPermission]
    let entryPoint: String
    let iconName: String?
    let widgetSizes: [String]
    
    init(
        id: String,
        name: String,
        version: String = "1.0.0",
        author: String,
        description: String,
        minAuraVersion: String = "1.0",
        permissions: [PluginPermission] = [],
        entryPoint: String = "main.js",
        iconName: String? = nil,
        widgetSizes: [String] = ["small"]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.minAuraVersion = minAuraVersion
        self.permissions = permissions
        self.entryPoint = entryPoint
        self.iconName = iconName
        self.widgetSizes = widgetSizes
    }
}

/// Permissions a plugin can request
enum PluginPermission: String, Codable {
    case network = "network"           // Make HTTP requests
    case filesystem = "filesystem"     // Read/write files
    case notifications = "notifications" // Show notifications
    case calendar = "calendar"         // Access calendar
    case systemInfo = "systemInfo"     // Read system info
    case shortcuts = "shortcuts"       // Run Shortcuts
    case applescript = "applescript"   // Run AppleScript
}

/// Protocol that all plugins must conform to
protocol AuraPlugin: ObservableObject, Identifiable {
    var id: String { get }
    var manifest: PluginManifest { get }
    var isLoaded: Bool { get }
    
    /// Initialize the plugin
    func load() async throws
    
    /// Clean up resources
    func unload()
    
    /// Get the widget view for this plugin
    func widgetView(size: WidgetSize) -> AnyView
    
    /// Handle a command from the AI
    func handleCommand(_ command: String) async -> String?
    
    /// Called when context changes
    func onContextChange(_ context: ContextSnapshot)
}

/// Base class for Swift-based plugins
class BasePlugin: AuraPlugin {
    let id: String
    let manifest: PluginManifest
    @Published var isLoaded: Bool = false
    
    init(manifest: PluginManifest) {
        self.id = manifest.id
        self.manifest = manifest
    }
    
    func load() async throws {
        isLoaded = true
    }
    
    func unload() {
        isLoaded = false
    }
    
    func widgetView(size: WidgetSize) -> AnyView {
        AnyView(
            Text(manifest.name)
                .font(.caption)
        )
    }
    
    func handleCommand(_ command: String) async -> String? {
        return nil
    }
    
    func onContextChange(_ context: ContextSnapshot) {
        // Override in subclass
    }
}

/// Error types for plugin operations
enum PluginError: Error, LocalizedError {
    case manifestNotFound
    case invalidManifest
    case loadFailed(String)
    case permissionDenied(PluginPermission)
    case incompatibleVersion
    case pluginNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .manifestNotFound:
            return "Plugin manifest.json not found"
        case .invalidManifest:
            return "Invalid plugin manifest format"
        case .loadFailed(let reason):
            return "Failed to load plugin: \(reason)"
        case .permissionDenied(let permission):
            return "Permission denied: \(permission.rawValue)"
        case .incompatibleVersion:
            return "Plugin requires a newer version of Aura"
        case .pluginNotFound(let id):
            return "Plugin not found: \(id)"
        }
    }
}

/// Installed plugin representation
struct InstalledPlugin: Identifiable {
    let id: String
    let manifest: PluginManifest
    let path: URL
    var isEnabled: Bool
    var plugin: (any AuraPlugin)?
}
