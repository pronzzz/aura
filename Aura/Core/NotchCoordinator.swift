import AppKit
import Combine

/// Creates one notch per target display and routes global pointer events to them.
@MainActor
final class NotchCoordinator {
    static let shared = NotchCoordinator()

    private(set) var controllers: [NotchController] = []
    private var monitors: [Any] = []
    private var cancellables = Set<AnyCancellable>()
    private var lastDisplayMode = ""
    private var dragChangeCount = 0
    private var dragHasPayload = false

    private init() {}

    func start() {
        rebuild()
        installMonitors()

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.rebuild() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if Pref.string(.displayMode) != self.lastDisplayMode { self.rebuild() }
                self.controllers.forEach { $0.viewModel.objectWillChange.send() }
                self.applyFullscreen()
            }
            .store(in: &cancellables)

        FullscreenMonitor.shared.onChange = { [weak self] in self?.applyFullscreen() }
    }

    func rebuild() {
        controllers.forEach { $0.teardown() }
        lastDisplayMode = Pref.string(.displayMode)
        controllers = targetScreens().map { NotchController(screen: $0) }
        applyFullscreen()
    }

    private func targetScreens() -> [NSScreen] {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return [] }
        switch DisplayMode(rawValue: Pref.string(.displayMode)) ?? .notched {
        case .all:
            return screens
        case .primary:
            return [primary]
        case .notched:
            let notched = screens.filter(\.hasNotch)
            return notched.isEmpty ? [primary] : notched
        }
    }

    private func applyFullscreen() {
        let hide = Pref.bool(.hideInFullscreen)
        for controller in controllers {
            let isFull = controller.displayID.map { FullscreenMonitor.shared.fullscreenDisplays.contains($0) } ?? false
            controller.setHiddenForFullscreen(hide && isFull)
        }
    }

    // MARK: - Commands

    /// The notch on the display under the pointer, or the first one.
    var activeController: NotchController? {
        let point = NSEvent.mouseLocation
        return controllers.first { $0.screen.frame.contains(point) } ?? controllers.first
    }

    func open(tab: NotchTab?) {
        guard let controller = activeController else { return }
        controller.viewModel.open(tab: tab)
        if tab == .ask { controller.focusPanel() }
    }

    func toggle(tab: NotchTab?) {
        guard let controller = activeController else { return }
        if controller.viewModel.isOpen, tab == nil || controller.viewModel.tab == tab {
            controller.viewModel.close()
        } else {
            open(tab: tab)
        }
    }

    func closeAll() {
        controllers.forEach { $0.viewModel.close() }
    }

    // MARK: - Event monitors

    private func installMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.route(event) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask.union(.scrollWheel), handler: { [weak self] event in
            MainActor.assumeIsolated { self?.route(event) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func route(_ event: NSEvent) {
        let point = NSEvent.mouseLocation
        switch event.type {
        case .leftMouseDown:
            dragChangeCount = NSPasteboard(name: .drag).changeCount
            dragHasPayload = false
        case .leftMouseDragged:
            if !dragHasPayload, NSPasteboard(name: .drag).changeCount != dragChangeCount {
                dragHasPayload = true
            }
            controllers.forEach { $0.handleDrag(point, hasPayload: dragHasPayload) }
        case .leftMouseUp:
            dragHasPayload = false
            controllers.forEach { $0.handleMouseUp() }
        case .scrollWheel:
            controllers.first { $0.screen.frame.contains(point) }?.handleScroll(event)
        default:
            controllers.forEach { $0.handleMouseMoved(point) }
        }
    }
}
