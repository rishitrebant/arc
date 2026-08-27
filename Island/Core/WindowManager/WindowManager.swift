import AppKit
import SwiftUI

/// Responsible ONLY for window creation, positioning, and visibility.
///
/// The window is created ONCE, sized to the maximum possible content
/// (expanded size + shadow canvas margin), positioned centered on the
/// notch and top-flush with the screen — and then NEVER MOVED OR RESIZED
/// AGAIN. This is a deliberate change from an earlier version of this
/// file, which smoothly animated the actual AppKit window frame between
/// compact and expanded sizes using a hand-rolled `SpringAnimator`, built
/// with physics matched to SwiftUI's own spring.
///
/// Matched physics were not enough. Even with identical stiffness/damping,
/// `SpringAnimator` (a manual Timer-driven physics loop) and SwiftUI's own
/// Core-Animation-backed spring are still two INDEPENDENT simulations on
/// two different clocks. Any tiny desync between them was nearly invisible
/// on a large-travel element (the waveform moves ~110pt between states)
/// but clearly visible on a small-travel one (the album art moves only
/// ~35pt) — same underlying desync, just proportionally much louder on the
/// smaller move. That's what caused the album art to visibly drift left
/// before catching up, while the waveform looked fine.
///
/// The fix is to remove the second animation system entirely. The window
/// itself is now static. `MusicIslandView`'s own `.frame(width:height:)` +
/// `.clipped()` — already driven by plain SwiftUI animation on `isExpanded`
/// — is the ONLY thing that visually grows or shrinks the pill. Since
/// that's a single Core Animation transaction driving the shape, every
/// piece of content, and (previously) the window all at once, there is
/// nothing left that CAN fall out of sync with anything else.
///
/// Known tradeoff, called out rather than hidden: the window's actual
/// clickable/hoverable AppKit-level bounds are now always the FULL
/// expanded size (plus the shadow margin), even while the visible pill is
/// still compact. `ignoresMouseEvents` must stay `false` for hover/click to
/// work at all, so that full area intercepts mouse events regardless of
/// what's currently visible within it — SwiftUI's own hit-testing (via
/// `.allowsHitTesting`/actual view bounds) still correctly limits which
/// parts of that area respond to hover, but menu bar items that happen to
/// sit underneath the invisible margin will be unreachable by click while
/// this window exists there. Previously this dead zone was only a small
/// shadow margin around the CURRENT size; now it's permanently as large as
/// the expanded card. If this becomes a real problem in practice, the
/// fix is scoping the window itself to a fixed region tight to actual
/// device notch bounds (already have `NSScreen.auxiliaryTopLeftArea`/
/// `auxiliaryTopRightArea` for this from a much earlier pass) sized to
/// fit the expanded card, rather than centering on the whole screen.
@MainActor
final class WindowManager {
    private var window: IslandWindow?

    private var expandedSize: CGSize {
        CGSize(width: DesignTokens.MusicMetrics.expandedWidth, height: DesignTokens.MusicMetrics.expandedHeight)
    }

    /// The static window canvas: max content size plus the shadow margin.
    /// See `DesignTokens.Shadow` for why the margin exists (room for the
    /// shadow to render into — AppKit clips all drawing to the window's
    /// frame, so a window sized exactly to visible content clips its own
    /// shadow to nothing).
    private var canvasSize: CGSize {
        CGSize(
            width: expandedSize.width + DesignTokens.Shadow.canvasInsetX * 2,
            height: expandedSize.height + DesignTokens.Shadow.canvasInsetBottom
        )
    }

    func present<Content: View>(_ rootView: Content) {
        let screen = notchScreen()
        let canvas = canvasSize
        let origin = notchOrigin(on: screen, size: canvas)

        let panel = window ?? IslandWindow(contentRect: NSRect(origin: origin, size: canvas))

        // The actual visible content (`rootView`, whose own size animates
        // internally between compact and expanded) is centered horizontally
        // and pinned to the top within this static, always-max-sized
        // canvas — matching exactly where it would have sat if the window
        // itself were still being resized around it. `.top` alignment =
        // horizontally centered, vertically top-anchored.
        let centeredRoot = rootView
            .padding(
                EdgeInsets(
                    top: 0,
                    leading: DesignTokens.Shadow.canvasInsetX,
                    bottom: DesignTokens.Shadow.canvasInsetBottom,
                    trailing: DesignTokens.Shadow.canvasInsetX
                )
            )
            .frame(width: canvas.width, height: canvas.height, alignment: .top)

        let hosting = NSHostingView(rootView: centeredRoot)
        hosting.frame = NSRect(origin: .zero, size: canvas)
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        window = panel
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func notchOrigin(on screen: NSScreen?, size: CGSize) -> NSPoint {
        guard let frame = screen?.frame else { return .zero }
        let x = (frame.midX - (size.width / 2)).rounded()
        let y = (frame.maxY - size.height).rounded()
        return NSPoint(x: x, y: y)
    }
}
