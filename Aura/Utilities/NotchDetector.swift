import AppKit
import Foundation

/// Detects whether the Mac has a notch and provides notch dimensions
class NotchDetector {
    
    struct NotchInfo {
        let hasNotch: Bool
        let width: CGFloat
        let height: CGFloat
        let position: NotchPosition
    }
    
    enum NotchPosition {
        case center(x: CGFloat, y: CGFloat)
        case none
    }
    
    static func detect(for screen: NSScreen) -> NotchInfo {
        // Check for notch using safe area insets (available on macOS 12+)
        if #available(macOS 12.0, *) {
            let topInset = screen.safeAreaInsets.top
            
            if topInset > 0 {
                // Has a notch! The safe area inset tells us the notch height
                let screenFrame = screen.frame
                
                // Standard notch dimensions (approximate)
                // MacBook Pro 14": ~200pt wide, ~32pt tall
                // MacBook Pro 16": ~200pt wide, ~32pt tall
                let notchWidth: CGFloat = 200
                let notchHeight = topInset
                
                // Notch is centered horizontally at the top
                let centerX = screenFrame.midX
                let centerY = screenFrame.maxY - (notchHeight / 2)
                
                return NotchInfo(
                    hasNotch: true,
                    width: notchWidth,
                    height: notchHeight,
                    position: .center(x: centerX, y: centerY)
                )
            }
        }
        
        // No notch detected - simulate one for visual consistency
        let screenFrame = screen.frame
        let simulatedWidth: CGFloat = 200
        let simulatedHeight: CGFloat = 30
        
        return NotchInfo(
            hasNotch: false,
            width: simulatedWidth,
            height: simulatedHeight,
            position: .center(x: screenFrame.midX, y: screenFrame.maxY - (simulatedHeight / 2))
        )
    }
    
    /// Calculate the ideal frame for the Aura panel based on notch presence
    static func calculatePanelFrame(for screen: NSScreen, expanded: Bool) -> NSRect {
        let notchInfo = detect(for: screen)
        let screenFrame = screen.frame
        
        // Panel dimensions
        let collapsedWidth: CGFloat = notchInfo.width
        let collapsedHeight: CGFloat = max(notchInfo.height, 36) // Minimum 36pt for content
        
        let expandedWidth: CGFloat = 400
        let expandedHeight: CGFloat = 200
        
        let width = expanded ? expandedWidth : collapsedWidth
        let height = expanded ? expandedHeight : collapsedHeight
        
        // Position calculation
        let x = screenFrame.midX - (width / 2)
        
        // In AppKit, Y=0 is at bottom of screen
        // screenFrame.maxY is the TOP of the screen
        // NSRect origin is bottom-left corner, so y = screenFrame.maxY - height puts TOP at screenFrame.maxY
        
        var y: CGFloat
        if notchInfo.hasNotch {
            // Position AT the absolute top of screen (behind/at the notch)
            // We want the TOP of our panel to be at screenFrame.maxY
            // Since origin is bottom-left, y = screenFrame.maxY - panelHeight
            y = screenFrame.maxY - height
        } else {
            // Simulate notch appearance at top with small gap
            y = screenFrame.maxY - height - 2
        }
        
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
