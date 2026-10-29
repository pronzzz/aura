import AppKit

/// Measures the real notch of a screen (or a simulated one) and the layout sizes Aura uses.
struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let hasHardwareNotch: Bool
    /// Size of the physical cut-out (or the simulated pill on displays without one).
    let notchSize: CGSize

    static let openWidth: CGFloat = 660
    static let openContentHeight: CGFloat = 200
    /// The panel never resizes; the SwiftUI shape animates inside it. Large enough for the open state plus shadow.
    static let panelSize = CGSize(width: 780, height: 340)

    init(screen: NSScreen) {
        self.init(frame: screen.frame,
                  safeTop: screen.safeAreaInsets.top,
                  leftArea: screen.auxiliaryTopLeftArea,
                  rightArea: screen.auxiliaryTopRightArea,
                  menuBarHeight: screen.frame.maxY - screen.visibleFrame.maxY)
    }

    init(frame: CGRect, safeTop: CGFloat, leftArea: CGRect?, rightArea: CGRect?, menuBarHeight: CGFloat) {
        screenFrame = frame
        if safeTop > 0, let left = leftArea, let right = rightArea {
            hasHardwareNotch = true
            let width = frame.width - left.width - right.width
            notchSize = CGSize(width: max(150, width), height: safeTop)
        } else {
            hasHardwareNotch = false
            let bar = menuBarHeight > 0 ? menuBarHeight : 24
            notchSize = CGSize(width: 190, height: min(max(bar, 22), 32))
        }
    }

    /// A stand-in geometry for previews and snapshots (14" MacBook Pro).
    static let preview = NotchGeometry(frame: CGRect(x: 0, y: 0, width: 1512, height: 982),
                                       safeTop: 32,
                                       leftArea: CGRect(x: 0, y: 950, width: 657, height: 32),
                                       rightArea: CGRect(x: 855, y: 950, width: 657, height: 32),
                                       menuBarHeight: 32)

    var panelFrame: CGRect {
        CGRect(x: screenFrame.midX - Self.panelSize.width / 2,
               y: screenFrame.maxY - Self.panelSize.height,
               width: Self.panelSize.width,
               height: Self.panelSize.height)
    }

    /// Screen-space rect of a top-centred shape of the given size.
    func screenRect(for size: CGSize) -> CGRect {
        CGRect(x: screenFrame.midX - size.width / 2,
               y: screenFrame.maxY - size.height,
               width: size.width,
               height: size.height)
    }
}
