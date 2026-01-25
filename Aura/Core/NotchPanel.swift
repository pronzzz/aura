import AppKit

/// Custom NSPanel subclass for the transparent notch overlay
/// Configured as a floating, borderless, transparent panel that doesn't steal focus
class NotchPanel: NSPanel {
    
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        configurePanel()
    }
    
    private func configurePanel() {
        // Transparency
        isOpaque = false
        backgroundColor = .clear
        
        // Floating behavior
        level = .floating
        
        // Don't hide when app loses focus
        hidesOnDeactivate = false
        
        // Can appear on all spaces
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        
        // Don't show in window list
        isExcludedFromWindowsMenu = true
        
        // Allow clicking through transparent areas
        ignoresMouseEvents = false
        
        // No shadow for the panel itself
        hasShadow = false
        
        // Accept mouse moved events for hover detection
        acceptsMouseMovedEvents = true
    }
    
    // Allow clicking through non-content areas
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
