import AppKit
import Combine
import SwiftUI

/// Owns the panel for one display and turns pointer activity into notch state.
///
/// The panel has a fixed size; only the SwiftUI shape inside animates. The panel ignores
/// mouse events unless the pointer is over the visible shape, so everything around the
/// notch stays clickable.
@MainActor
final class NotchController {
    let screen: NSScreen
    let viewModel: NotchViewModel
    private let panel: NotchPanel

    private var openWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()

    // Scroll gesture accumulation
    private var scrollX: CGFloat = 0
    private var scrollY: CGFloat = 0
    private var gestureCooldownUntil = Date.distantPast

    var displayID: CGDirectDisplayID? { screen.displayID }

    init(screen: NSScreen) {
        self.screen = screen
        let geometry = NotchGeometry(screen: screen)
        viewModel = NotchViewModel(geometry: geometry)
        panel = NotchPanel(contentRect: geometry.panelFrame)

        let root = NotchRootView(viewModel: viewModel)
        let host = NotchHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: geometry.panelFrame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        panel.setFrame(geometry.panelFrame, display: false)
        panel.orderFrontRegardless()

        panel.onCancel = { [weak self] in self?.viewModel.close() }

        NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification, object: panel)
            .sink { [weak self] _ in
                guard let self, self.viewModel.tab == .ask, self.viewModel.isOpen else { return }
                self.viewModel.hold("typing", false)
                self.reevaluate()
            }
            .store(in: &cancellables)

        // Any state change can move the shape under a stationary pointer.
        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.reevaluate() }
            .store(in: &cancellables)

        viewModel.$isOpen.removeDuplicates().sink { [weak self] open in
            guard let self else { return }
            if open {
                self.panel.ignoresMouseEvents = false
                if self.viewModel.tab == .ask { self.focusPanel() }
            } else if self.panel.isKeyWindow {
                self.panel.resignKey()
            }
        }
        .store(in: &cancellables)

        viewModel.$tab.removeDuplicates().sink { [weak self] tab in
            guard let self, tab == .ask, self.viewModel.isOpen else { return }
            self.focusPanel()
        }
        .store(in: &cancellables)
    }

    func teardown() {
        cancellables.removeAll()
        openWork?.cancel()
        closeWork?.cancel()
        panel.orderOut(nil)
        panel.close()
    }

    func focusPanel() {
        panel.makeKey()
    }

    // MARK: - Pointer

    func reevaluate() {
        handleMouseMoved(NSEvent.mouseLocation)
    }

    func handleMouseMoved(_ point: NSPoint) {
        guard !viewModel.isHiddenForFullscreen else {
            panel.ignoresMouseEvents = true
            return
        }

        let shape = viewModel.shapeScreenRect
        let overShape = shape.insetBy(dx: -2, dy: -2).contains(point)
        panel.ignoresMouseEvents = !(overShape || viewModel.isDragTargeting)

        if viewModel.isOpen {
            let keepZone = shape.insetBy(dx: -16, dy: -16)
            if keepZone.contains(point) || viewModel.isHeld {
                cancelClose()
            } else {
                scheduleClose()
            }
        } else if Pref.bool(.openOnHover), viewModel.hoverTriggerRect.contains(point) {
            scheduleOpen()
        } else {
            cancelOpen()
        }
    }

    func handleDrag(_ point: NSPoint, hasPayload: Bool) {
        guard hasPayload, !viewModel.isHiddenForFullscreen else { return }
        let zone = viewModel.isOpen
            ? viewModel.shapeScreenRect.insetBy(dx: -24, dy: -24)
            : viewModel.hoverTriggerRect.insetBy(dx: -50, dy: -24)

        if zone.contains(point) {
            cancelClose()
            if !viewModel.isDragTargeting { viewModel.isDragTargeting = true }
            panel.ignoresMouseEvents = false
            if !viewModel.isOpen { viewModel.open(tab: .tray) } else if viewModel.tab != .tray { viewModel.tab = .tray }
        } else if viewModel.isDragTargeting {
            viewModel.isDragTargeting = false
            scheduleClose()
        }
    }

    func handleMouseUp() {
        guard viewModel.isDragTargeting else { return }
        // Give the drop a moment to land before releasing the hold.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.viewModel.isDragTargeting = false
            self?.reevaluate()
        }
    }

    func handleScroll(_ event: NSEvent) {
        guard Pref.bool(.gesturesEnabled), !viewModel.isOpen, Date() > gestureCooldownUntil else { return }
        guard viewModel.shapeScreenRect.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation) else { return }

        if event.phase == .began || event.phase == .mayBegin {
            scrollX = 0
            scrollY = 0
        }
        // Normalise so positive Y means "fingers moved down" regardless of natural scrolling.
        let dy = event.isDirectionInvertedFromDevice ? event.scrollingDeltaY : -event.scrollingDeltaY
        let dx = event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
        scrollX += dx
        scrollY += dy

        if scrollY > 28, abs(scrollY) > abs(scrollX) {
            fireGesture { viewModel.open() }
        } else if abs(scrollX) > 60, abs(scrollX) > abs(scrollY) * 1.5,
                  NowPlayingService.shared.track != nil {
            let forward = (scrollX < 0) != Pref.bool(.invertMediaGestures)
            fireGesture {
                if forward { NowPlayingService.shared.next() } else { NowPlayingService.shared.previous() }
                Haptics.tap()
            }
        }
        if event.phase == .ended || event.phase == .cancelled {
            scrollX = 0
            scrollY = 0
        }
    }

    private func fireGesture(_ action: () -> Void) {
        scrollX = 0
        scrollY = 0
        gestureCooldownUntil = Date().addingTimeInterval(0.6)
        action()
    }

    // MARK: - Fullscreen

    func setHiddenForFullscreen(_ hidden: Bool) {
        guard viewModel.isHiddenForFullscreen != hidden else { return }
        viewModel.isHiddenForFullscreen = hidden
        if hidden { viewModel.close() }
        panel.alphaValue = hidden ? 0 : 1
    }

    // MARK: - Timers

    private func scheduleOpen() {
        guard openWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.openWork = nil
            if self.viewModel.hoverTriggerRect.contains(NSEvent.mouseLocation) {
                self.viewModel.open()
            }
        }
        openWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.02, Pref.double(.hoverDelay)), execute: work)
    }

    private func cancelOpen() {
        openWork?.cancel()
        openWork = nil
    }

    private func scheduleClose() {
        guard closeWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.closeWork = nil
            let keep = self.viewModel.shapeScreenRect.insetBy(dx: -16, dy: -16).contains(NSEvent.mouseLocation)
            if !keep, !self.viewModel.isHeld { self.viewModel.close() }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
    }

    private func cancelClose() {
        closeWork?.cancel()
        closeWork = nil
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    var hasNotch: Bool {
        safeAreaInsets.top > 0 && auxiliaryTopLeftArea != nil
    }
}
