import SwiftUI
import Combine

/// Manages theme/appearance settings and observes system appearance changes
class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @Published var isDarkMode: Bool = true
    @Published var accentColor: Color = .blue
    
    private var appearanceObserver: NSKeyValueObservation?
    
    private init() {
        // Get initial appearance
        updateAppearance()
        
        // Observe system appearance changes
        appearanceObserver = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateAppearance()
            }
        }
    }
    
    private func updateAppearance() {
        let appearance = NSApp.effectiveAppearance
        isDarkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
    
    // MARK: - Theme Colors
    
    var textColor: Color {
        isDarkMode ? .white : .black
    }
    
    var secondaryTextColor: Color {
        isDarkMode ? Color.white.opacity(0.7) : Color.black.opacity(0.6)
    }
    
    var backgroundColor: Color {
        isDarkMode ? Color.black.opacity(0.85) : Color.white.opacity(0.9)
    }
    
    var widgetBackground: Color {
        isDarkMode ? Color.white.opacity(0.1) : Color.black.opacity(0.05)
    }
    
    var dividerColor: Color {
        isDarkMode ? Color.white.opacity(0.2) : Color.black.opacity(0.1)
    }
}
