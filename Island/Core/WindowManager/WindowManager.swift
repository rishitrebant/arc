import AppKit
import SwiftUI

/// Responsible ONLY for window creation, positioning, visibility, and
/// display synchronization.
///
/// The window is permanently anchored to the physical notch.
/// Compact position is calculated once.
/// During expansion only the size changes while the top edge remains fixed.
@MainActor
final class WindowManager {

    private var window: IslandWindow?

    /// Original compact position.
    private var compactOrigin: NSPoint?

    private let defaultCompactSize = CGSize(
        width: DesignTokens.MusicMetrics.compactWidth,
        height: DesignTokens.MusicMetrics.compactHeight
    )

    func present<Content: View>(_ rootView: Content) {

        let screen = notchScreen()
        let origin = notchOrigin(
            on: screen,
            size: defaultCompactSize
        )

        compactOrigin = origin

        let panel = window ??
        IslandWindow(
            contentRect: NSRect(
                origin: origin,
                size: defaultCompactSize
            )
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(
            origin: .zero,
            size: defaultCompactSize
        )

        panel.contentView = hosting
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        window = panel
    }

    /// Keeps the TOP EDGE fixed.
    /// Width grows symmetrically.
    /// Height grows downward only.
    func resize(to size: CGSize) {

        guard
            let window,
            let compactOrigin,
            size.width > 0,
            size.height > 0
        else {
            return
        }

        let widthDifference = size.width - defaultCompactSize.width
        let heightDifference = size.height - defaultCompactSize.height

        let newOrigin = NSPoint(
            x: compactOrigin.x - widthDifference / 2,
            y: compactOrigin.y - heightDifference
        )

        let frame = NSRect(
            origin: newOrigin,
            size: size
        )

        window.setFrame(
            frame,
            display: true,
            animate: false
        )

        window.contentView?.frame = NSRect(
            origin: .zero,
            size: size
        )
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func notchOrigin(
        on screen: NSScreen?,
        size: CGSize
    ) -> NSPoint {

        guard let frame = screen?.frame else {
            return .zero
        }

        let x = (frame.midX - size.width / 2).rounded()
        let y = (frame.maxY - size.height).rounded()

        return NSPoint(x: x, y: y)
    }
}
