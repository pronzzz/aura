import AppKit
import SwiftUI

/// Manages the notch panel lifecycle and positioning
class NotchWindowController: NSWindowController {
    private let screen: NSScreen
    private let viewModel = NotchViewModel()
    
    init(screen: NSScreen) {
        self.screen = screen
        
        // Calculate initial frame
        let frame = Self.calculateNotchFrame(for: screen, expanded: false)
        
        // Create the panel
        let panel = NotchPanel(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        super.init(window: panel)
        
        // Setup SwiftUI content
        let contentView = NSHostingView(rootView: 
            NotchView(viewModel: viewModel)
                .onHover { [weak self] isHovering in
                    self?.handleHover(isHovering)
                }
        )
        contentView.frame = panel.contentView?.bounds ?? .zero
        contentView.autoresizingMask = [.width, .height]
        
        panel.contentView = contentView
        
        // Position the window
        positionWindow(expanded: false)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Window Positioning
    
    private static func calculateNotchFrame(for screen: NSScreen, expanded: Bool) -> NSRect {
        return NotchDetector.calculatePanelFrame(for: screen, expanded: expanded)
    }
    
    private func positionWindow(expanded: Bool) {
        guard let window = window else { return }
        
        let frame = Self.calculateNotchFrame(for: screen, expanded: expanded)
        
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        }
    }
    
    // MARK: - Hover Handling
    
    private func handleHover(_ isHovering: Bool) {
        // Dispatch to next runloop to avoid layout recursion errors
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Only update if changed to avoid unnecessary layout cycles
            if self.viewModel.isExpanded != isHovering {
                self.viewModel.isExpanded = isHovering
                self.positionWindow(expanded: isHovering)
            }
        }
    }
}

// MARK: - ViewModel

class NotchViewModel: ObservableObject {
    @Published var isExpanded: Bool = false
    @Published var isVisible: Bool = true
}
