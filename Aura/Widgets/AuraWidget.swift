import SwiftUI

/// Size options for widgets
enum WidgetSize: String, CaseIterable, Codable {
    case small      // Icon only, minimal space
    case medium     // Icon + label
    case expanded   // Full info + controls
    
    var width: CGFloat {
        switch self {
        case .small: return 32
        case .medium: return 60
        case .expanded: return 120
        }
    }
}

/// Priority level for contextual widget surfacing
enum WidgetPriority: Int, Comparable {
    case low = 0
    case normal = 50
    case high = 75
    case critical = 100
    
    static func < (lhs: WidgetPriority, rhs: WidgetPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Protocol defining the widget interface
/// All widgets must conform to this protocol to be displayed in the notch
protocol AuraWidget: Identifiable, ObservableObject {
    /// Unique identifier for this widget instance
    var id: UUID { get }
    
    /// Display name of the widget
    var name: String { get }
    
    /// Icon name (SF Symbols)
    var iconName: String { get }
    
    /// Current size of the widget
    var size: WidgetSize { get set }
    
    /// Priority for display ordering (higher = more important)
    var priority: WidgetPriority { get set }
    
    /// Whether the widget is enabled
    var isEnabled: Bool { get set }
    
    /// The view body of the widget
    associatedtype Content: View
    @ViewBuilder func body(for size: WidgetSize) -> Content
    
    /// Lifecycle methods
    func onAppear()
    func onDisappear()
    func refresh()
}

// Default implementations
extension AuraWidget {
    func onAppear() {}
    func onDisappear() {}
    func refresh() {}
}

/// Type-erased wrapper for AuraWidget to store in collections
struct AnyAuraWidget: Identifiable {
    let id: UUID
    let name: String
    let iconName: String
    var size: WidgetSize
    var priority: WidgetPriority
    var isEnabled: Bool
    
    private let _bodyBuilder: (WidgetSize) -> AnyView
    private let _onAppear: () -> Void
    private let _onDisappear: () -> Void
    private let _refresh: () -> Void
    
    init<W: AuraWidget>(_ widget: W) {
        self.id = widget.id
        self.name = widget.name
        self.iconName = widget.iconName
        self.size = widget.size
        self.priority = widget.priority
        self.isEnabled = widget.isEnabled
        
        self._bodyBuilder = { size in AnyView(widget.body(for: size)) }
        self._onAppear = widget.onAppear
        self._onDisappear = widget.onDisappear
        self._refresh = widget.refresh
    }
    
    func body(for size: WidgetSize) -> AnyView {
        _bodyBuilder(size)
    }
    
    func onAppear() { _onAppear() }
    func onDisappear() { _onDisappear() }
    func refresh() { _refresh() }
}
