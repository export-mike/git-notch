import AppKit

/// Where to place the bar relative to the physical notch (or a synthetic one
/// on notch-less displays).
struct NotchLayout {
    let screen: NSScreen
    let hasNotch: Bool
    let barHeight: CGFloat       // menu-bar height
    let notchWidth: CGFloat      // width of the dead zone in the middle
    let clusterWidth: CGFloat    // width of each icon cluster flanking the notch

    var windowWidth: CGFloat { notchWidth + clusterWidth * 2 }

    /// Full window frame, in global (bottom-left origin) screen coordinates.
    var windowFrame: CGRect {
        let f = screen.frame
        return CGRect(
            x: f.midX - windowWidth / 2,
            y: f.maxY - barHeight,
            width: windowWidth,
            height: barHeight
        )
    }

    /// Global x of a cluster's horizontal centre — used to anchor dropdowns.
    func clusterCenterX(_ side: Side) -> CGFloat {
        let f = windowFrame
        switch side {
        case .left:  return f.minX + clusterWidth / 2
        case .right: return f.maxX - clusterWidth / 2
        }
    }

    static func current() -> NotchLayout {
        // Prefer a display that actually has a notch.
        let notched = NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
        let screen = notched ?? NSScreen.main ?? NSScreen.screens.first!
        let inset = screen.safeAreaInsets.top

        if inset > 0 {
            // Real notch: derive its width from the auxiliary top areas.
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            let derived = screen.frame.width - left - right
            let notchWidth = (derived > 40 && derived < 420) ? derived : 220
            return NotchLayout(
                screen: screen,
                hasNotch: true,
                barHeight: inset,
                notchWidth: notchWidth,
                clusterWidth: 46
            )
        } else {
            // No notch: render a small floating pill centred at the top.
            let barHeight = NSStatusBar.system.thickness > 0 ? NSStatusBar.system.thickness : 24
            return NotchLayout(
                screen: screen,
                hasNotch: false,
                barHeight: max(barHeight, 24),
                notchWidth: 8,
                clusterWidth: 46
            )
        }
    }
}
