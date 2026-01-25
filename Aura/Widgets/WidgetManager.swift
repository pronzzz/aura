import SwiftUI
import Combine

/// Central manager for widget lifecycle, registration, ordering, and persistence
class WidgetManager: ObservableObject {
    static let shared = WidgetManager()
    
    /// All registered widgets
    @Published var widgets: [AnyAuraWidget] = []
    
    /// Widgets filtered by enabled status and sorted by priority
    var activeWidgets: [AnyAuraWidget] {
        widgets
            .filter { $0.isEnabled }
            .sorted { $0.priority > $1.priority }
    }
    
    /// UserDefaults key for widget order persistence
    private let widgetOrderKey = "widgetOrder"
    private let widgetEnabledKey = "widgetEnabled"
    
    private init() {
        registerBuiltinWidgets()
        loadWidgetState()
    }
    
    // MARK: - Widget Registration
    
    func register<W: AuraWidget>(_ widget: W) {
        let wrapped = AnyAuraWidget(widget)
        if !widgets.contains(where: { $0.id == wrapped.id }) {
            widgets.append(wrapped)
        }
    }
    
    private func registerBuiltinWidgets() {
        register(ClockWidget())
        register(BatteryWidget())
        register(WiFiWidget())
        register(MusicWidget())
        register(CalendarWidget())
        register(SystemStatsWidget())
    }
    
    // MARK: - Widget State Management
    
    func toggleWidget(id: UUID) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].isEnabled.toggle()
            saveWidgetState()
        }
    }
    
    func reorderWidgets(from source: IndexSet, to destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
        saveWidgetState()
    }
    
    func setSize(for id: UUID, size: WidgetSize) {
        if let index = widgets.firstIndex(where: { $0.id == id }) {
            widgets[index].size = size
            saveWidgetState()
        }
    }
    
    // MARK: - Persistence
    
    private func saveWidgetState() {
        let order = widgets.map { $0.id.uuidString }
        let enabled = Dictionary(uniqueKeysWithValues: widgets.map { ($0.id.uuidString, $0.isEnabled) })
        
        UserDefaults.standard.set(order, forKey: widgetOrderKey)
        UserDefaults.standard.set(enabled, forKey: widgetEnabledKey)
    }
    
    private func loadWidgetState() {
        guard let order = UserDefaults.standard.array(forKey: widgetOrderKey) as? [String],
              let enabled = UserDefaults.standard.dictionary(forKey: widgetEnabledKey) as? [String: Bool] else {
            return
        }
        
        // Reorder widgets based on saved order
        widgets.sort { widget1, widget2 in
            let index1 = order.firstIndex(of: widget1.id.uuidString) ?? Int.max
            let index2 = order.firstIndex(of: widget2.id.uuidString) ?? Int.max
            return index1 < index2
        }
        
        // Apply enabled state
        for (index, widget) in widgets.enumerated() {
            if let isEnabled = enabled[widget.id.uuidString] {
                widgets[index].isEnabled = isEnabled
            }
        }
    }
    
    // MARK: - Lifecycle
    
    func refreshAll() {
        for widget in activeWidgets {
            widget.refresh()
        }
    }
}
