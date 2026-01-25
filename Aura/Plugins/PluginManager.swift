import Foundation
import Combine

/// Manages plugin discovery, loading, and lifecycle
class PluginManager: ObservableObject {
    static let shared = PluginManager()
    
    @Published var installedPlugins: [InstalledPlugin] = []
    @Published var isLoading: Bool = false
    
    private let pluginsDirectory: URL
    private let enabledPluginsKey = "aura_enabled_plugins"
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Plugins directory in Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        pluginsDirectory = appSupport.appendingPathComponent("Aura/Plugins", isDirectory: true)
        
        // Create directory if needed
        try? FileManager.default.createDirectory(at: pluginsDirectory, withIntermediateDirectories: true)
        
        // Load plugins
        Task {
            await discoverPlugins()
        }
    }
    
    // MARK: - Discovery
    
    func discoverPlugins() async {
        await MainActor.run { isLoading = true }
        
        var discovered: [InstalledPlugin] = []
        let enabledIds = enabledPluginIds
        
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: pluginsDirectory,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
            
            for url in contents {
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    if let plugin = await loadPluginManifest(from: url) {
                        var installed = plugin
                        installed.isEnabled = enabledIds.contains(plugin.id)
                        discovered.append(installed)
                    }
                }
            }
        } catch {
            print("Error discovering plugins: \(error)")
        }
        
        // Add built-in plugins
        discovered.append(contentsOf: builtInPlugins)
        
        await MainActor.run {
            installedPlugins = discovered
            isLoading = false
        }
        
        // Load enabled plugins
        for plugin in discovered where plugin.isEnabled {
            await loadPlugin(id: plugin.id)
        }
    }
    
    private func loadPluginManifest(from directory: URL) async -> InstalledPlugin? {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(PluginManifest.self, from: data)
            
            return InstalledPlugin(
                id: manifest.id,
                manifest: manifest,
                path: directory,
                isEnabled: false,
                plugin: nil
            )
        } catch {
            print("Error loading manifest from \(directory): \(error)")
            return nil
        }
    }
    
    // MARK: - Plugin Loading
    
    func loadPlugin(id: String) async {
        guard let index = installedPlugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        let installed = installedPlugins[index]
        
        // Check if it's a built-in plugin
        if let builtIn = createBuiltInPlugin(for: installed.manifest) {
            do {
                try await builtIn.load()
                await MainActor.run {
                    installedPlugins[index].plugin = builtIn
                    installedPlugins[index].isEnabled = true
                    saveEnabledPlugins()
                }
            } catch {
                print("Error loading built-in plugin \(id): \(error)")
            }
            return
        }
        
        // External plugins would be loaded here
        // For now, we only support built-in Swift plugins
    }
    
    func unloadPlugin(id: String) async {
        guard let index = installedPlugins.firstIndex(where: { $0.id == id }) else {
            return
        }
        
        installedPlugins[index].plugin?.unload()
        
        await MainActor.run {
            installedPlugins[index].plugin = nil
            installedPlugins[index].isEnabled = false
            saveEnabledPlugins()
        }
    }
    
    func togglePlugin(id: String) async {
        guard let plugin = installedPlugins.first(where: { $0.id == id }) else {
            return
        }
        
        if plugin.isEnabled {
            await unloadPlugin(id: id)
        } else {
            await loadPlugin(id: id)
        }
    }
    
    // MARK: - Plugin API
    
    func getPlugin(id: String) -> (any AuraPlugin)? {
        installedPlugins.first(where: { $0.id == id })?.plugin
    }
    
    func getEnabledPlugins() -> [any AuraPlugin] {
        installedPlugins.compactMap { $0.plugin }
    }
    
    /// Forward context changes to all enabled plugins
    func notifyContextChange(_ context: ContextSnapshot) {
        for plugin in getEnabledPlugins() {
            plugin.onContextChange(context)
        }
    }
    
    /// Send command to plugins and get responses
    func handleCommand(_ command: String) async -> [String] {
        var responses: [String] = []
        
        for plugin in getEnabledPlugins() {
            if let response = await plugin.handleCommand(command) {
                responses.append("[\(plugin.manifest.name)] \(response)")
            }
        }
        
        return responses
    }
    
    // MARK: - Persistence
    
    private var enabledPluginIds: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: enabledPluginsKey) ?? [])
    }
    
    private func saveEnabledPlugins() {
        let enabled = installedPlugins.filter { $0.isEnabled }.map { $0.id }
        UserDefaults.standard.set(enabled, forKey: enabledPluginsKey)
    }
    
    // MARK: - Built-in Plugins
    
    private var builtInPlugins: [InstalledPlugin] {
        let manifests = [
            PluginManifest(
                id: "com.aura.pomodoro",
                name: "Pomodoro Timer",
                author: "Aura",
                description: "Focus timer with work/break intervals",
                permissions: [.notifications],
                widgetSizes: ["small", "medium"]
            ),
            PluginManifest(
                id: "com.aura.weather",
                name: "Weather",
                author: "Aura",
                description: "Current weather conditions",
                permissions: [.network],
                widgetSizes: ["small", "medium", "expanded"]
            ),
            PluginManifest(
                id: "com.aura.clipboard",
                name: "Clipboard History",
                author: "Aura",
                description: "Quick access to clipboard history",
                permissions: [],
                widgetSizes: ["expanded"]
            )
        ]
        
        return manifests.map { manifest in
            InstalledPlugin(
                id: manifest.id,
                manifest: manifest,
                path: Bundle.main.bundleURL,
                isEnabled: false,
                plugin: nil
            )
        }
    }
    
    private func createBuiltInPlugin(for manifest: PluginManifest) -> (any AuraPlugin)? {
        switch manifest.id {
        case "com.aura.pomodoro":
            return PomodoroPlugin(manifest: manifest)
        case "com.aura.weather":
            return WeatherPlugin(manifest: manifest)
        case "com.aura.clipboard":
            return ClipboardPlugin(manifest: manifest)
        default:
            return nil
        }
    }
}
