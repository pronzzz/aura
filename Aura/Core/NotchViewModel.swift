import AppKit
import Combine
import SwiftUI

/// UI state of one notch (one per display).
@MainActor
final class NotchViewModel: ObservableObject {
    enum Phase: Equatable {
        case closed
        case peek
        case open
    }

    let geometry: NotchGeometry

    @Published private(set) var isOpen = false
    @Published var tab: NotchTab
    /// A file/text drag is hovering the notch.
    @Published var isDragTargeting = false
    /// Hidden because another app is fullscreen on this display.
    @Published var isHiddenForFullscreen = false
    /// Mirror (camera) replaces the calendar card while on.
    @Published var showMirror = false

    @Published private(set) var activity: LiveActivityKind?
    @Published private(set) var peek: Peek?

    /// Reasons that keep the notch open even when the pointer leaves (typing, menus…).
    @Published private(set) var holds = Set<String>()

    private var cancellables = Set<AnyCancellable>()

    init(geometry: NotchGeometry, observeCenter: Bool = true) {
        self.geometry = geometry
        let initial = Pref.bool(.rememberLastTab) ? Pref.string(.lastTab) : Pref.string(.defaultTab)
        self.tab = NotchTab(rawValue: initial) ?? .nook

        if observeCenter {
            let center = ActivityCenter.shared
            center.$current.removeDuplicates().sink { [weak self] in self?.activity = $0 }.store(in: &cancellables)
            center.$peek.sink { [weak self] in self?.peek = $0 }.store(in: &cancellables)
        }

        $tab.dropFirst().sink { tab in
            if !Runtime.isSnapshot { Pref.set(tab.rawValue, .lastTab) }
        }
        .store(in: &cancellables)
    }

    /// Used by previews and the snapshot renderer.
    func configureForPreview(open: Bool, tab: NotchTab, activity: LiveActivityKind?, peek: Peek?) {
        self.isOpen = open
        self.tab = tab
        self.activity = activity
        self.peek = peek
    }

    // MARK: - Phase

    var phase: Phase {
        if isOpen { return .open }
        if peek != nil, Pref.bool(.quickPeekEnabled) { return .peek }
        return .closed
    }

    func open(tab: NotchTab? = nil) {
        if let tab { self.tab = tab }
        guard !isOpen else { return }
        isOpen = true
        Haptics.tap()
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        isDragTargeting = false
        showMirror = false
        holds.removeAll()
    }

    func hold(_ reason: String, _ active: Bool) {
        if active { holds.insert(reason) } else { holds.remove(reason) }
    }

    var isHeld: Bool { !holds.isEmpty || isDragTargeting }

    // MARK: - Layout

    var notchWidth: CGFloat { geometry.notchSize.width }
    var notchHeight: CGFloat { geometry.notchSize.height }

    /// Width of each "wing" beside the physical notch when a live activity shows.
    var wingWidth: CGFloat { notchHeight + 12 }

    var topRadius: CGFloat {
        switch phase {
        case .open: return 14
        case .peek: return 10
        case .closed: return geometry.hasHardwareNotch ? 6 : 8
        }
    }

    var bottomRadius: CGFloat {
        switch phase {
        case .open: return 26
        case .peek: return 18
        case .closed: return geometry.hasHardwareNotch ? 10 : notchHeight / 2.2
        }
    }

    /// Size of the body (without the flared top corners).
    var bodySize: CGSize {
        switch phase {
        case .open:
            return CGSize(width: NotchGeometry.openWidth, height: notchHeight + NotchGeometry.openContentHeight)
        case .peek:
            return CGSize(width: max(notchWidth + wingWidth * 2 + 80, 380), height: notchHeight + 46)
        case .closed:
            if activity != nil {
                return CGSize(width: notchWidth + wingWidth * 2, height: notchHeight)
            }
            return geometry.notchSize
        }
    }

    /// Full shape size including the flared top corners.
    var shapeSize: CGSize {
        let body = bodySize
        return CGSize(width: body.width + topRadius * 2, height: body.height)
    }

    /// The closed notch is invisible on displays without a notch when the fake notch is off.
    var isInvisible: Bool {
        if isHiddenForFullscreen { return true }
        return phase == .closed && activity == nil && !geometry.hasHardwareNotch && !Pref.bool(.showFakeNotch)
    }

    var shapeScreenRect: CGRect { geometry.screenRect(for: shapeSize) }

    /// Region where hovering opens the notch.
    var hoverTriggerRect: CGRect {
        if isInvisible {
            let strip = CGSize(width: notchWidth + 40, height: 6)
            return geometry.screenRect(for: strip)
        }
        return shapeScreenRect.insetBy(dx: -4, dy: -2)
    }
}

// MARK: - Live activity models

enum LiveActivityKind: Equatable {
    case music
    case charging
    case lowBattery
    case timer
}

struct Peek: Equatable, Identifiable {
    enum Kind: Equatable {
        case music, power, timer, meeting, info, update
    }

    let id = UUID()
    var kind: Kind
    var title: String
    var subtitle: String
    var icon: String
    var tint: Color = .white
    var artwork: NSImage?

    static func == (lhs: Peek, rhs: Peek) -> Bool { lhs.id == rhs.id }
}
