import AppKit
import Combine
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Pref.registerDefaults()
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared

        // Services
        PowerService.shared.start()
        NowPlayingService.shared.start()
        CalendarService.shared.start()
        TimerService.shared.restore()
        ActivityCenter.shared.start()
        WorkflowEngine.shared.start()
        FullscreenMonitor.shared.start()

        // UI
        NotchCoordinator.shared.start()
        HotKeyCenter.shared.install()
        updateStatusItemVisibility()

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.updateStatusItemVisibility() }
            .store(in: &cancellables)

        if !Pref.bool(.onboardingDone) {
            OnboardingWindowController.shared.show()
        }

        if Pref.bool(.checkForUpdates) {
            Task { await UpdateChecker.shared.check(userInitiated: false) }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "aura" {
            switch url.host {
            case "settings": SettingsWindowController.shared.show()
            case "ask": NotchCoordinator.shared.open(tab: .ask)
            case "tray": NotchCoordinator.shared.open(tab: .tray)
            case "tasks": NotchCoordinator.shared.open(tab: .tasks)
            default: NotchCoordinator.shared.open(tab: nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Status item

    private func updateStatusItemVisibility() {
        let show = Pref.bool(.showMenuBarIcon)
        if show, statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "Aura")
                ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Aura")
            let menu = NSMenu()
            menu.delegate = self
            item.menu = menu
            statusItem = item
        } else if !show, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if let release = UpdateChecker.shared.available {
            let update = NSMenuItem(title: "Update Available: Aura \(release.version)…", action: #selector(openUpdate), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
            menu.addItem(.separator())
        }

        menu.addItem(item("Open Aura", #selector(openNotch), key: "n", modifiers: [.control, .option]))
        menu.addItem(item("Ask Aura", #selector(openAsk), key: "a", modifiers: [.control, .option]))
        menu.addItem(item("Show Tray", #selector(openTray)))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Check for Updates…", #selector(checkUpdates)))
        menu.addItem(item("About Aura", #selector(openAbout)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Aura", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = [.command]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func openNotch() { NotchCoordinator.shared.open(tab: nil) }
    @objc private func openAsk() { NotchCoordinator.shared.open(tab: .ask) }
    @objc private func openTray() { NotchCoordinator.shared.open(tab: .tray) }
    @objc private func openSettings() { SettingsWindowController.shared.show() }
    @objc private func openAbout() { SettingsWindowController.shared.show(section: .about) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func checkUpdates() {
        Task {
            await UpdateChecker.shared.check(userInitiated: true)
        }
    }

    @objc private func openUpdate() {
        if let url = UpdateChecker.shared.available?.url { NSWorkspace.shared.open(url) }
    }
}

/// Shows Aura's own notifications even while the app is "active".
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    static func post(title: String, body: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
