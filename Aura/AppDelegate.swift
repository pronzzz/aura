import AppKit
import SwiftUI
import Combine

class AppDelegate: NSObject, NSApplicationDelegate {
    private var notchWindowController: NotchWindowController?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Setup menu bar item
        setupStatusItem()
        
        // Create notch window on main screen
        setupNotchWindow()
        
        // Listen for screen changes
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.handleScreenChange()
            }
            .store(in: &cancellables)
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Aura")
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Aura", action: #selector(showNotch), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Hide Aura", action: #selector(hideNotch), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Aura", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    private func setupNotchWindow() {
        guard let screen = NSScreen.main else { return }
        
        // Check if this screen has a notch
        if hasNotch(screen: screen) {
            notchWindowController = NotchWindowController(screen: screen)
            notchWindowController?.showWindow(nil)
        }
    }
    
    private func hasNotch(screen: NSScreen) -> Bool {
        // Check for safe area insets that indicate a notch
        // On notched MacBooks, safeAreaInsets.top > 0
        if #available(macOS 12.0, *) {
            return screen.safeAreaInsets.top > 0
        }
        return false
    }
    
    private func handleScreenChange() {
        // Reconfigure notch window when screens change
        notchWindowController?.close()
        setupNotchWindow()
    }
    
    @objc private func showNotch() {
        notchWindowController?.showWindow(nil)
    }
    
    @objc private func hideNotch() {
        notchWindowController?.close()
    }
    
    @objc private func openSettings() {
        if let url = URL(string: "aura://settings") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
