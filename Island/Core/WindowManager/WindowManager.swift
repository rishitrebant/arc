import AppKit
import SwiftUI

/// Responsible ONLY for window creation, positioning, visibility, and
/// mouse-event pass-through.
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
/// ~35pt). The fix was removing the second animation system entirely —
/// `MusicIslandView`'s own `.frame(width:height:)` + `.clipped()` is now
/// the ONLY thing driving the visible size.
///
/// CLICK-THROUGH (this pass): a static window intercepting mouse events
/// across its FULL bounds — which it does whenever `ignoresMouseEvents`
/// is `false`, needed for hover/click to work at all — silently eats
/// clicks meant for menu bar items under the transparent shadow margin and
/// the reserved-but-not-yet-visible expanded area.
///
/// A previous attempt at this fixed it by overriding `hitTest(_:)` on a
/// custom `NSView` to reject points outside the active region. That does
/// NOT achieve click-through — `hitTest` only decides which subview
/// *within this window* handles an event; the window itself, being
/// topmost and not ignoring mouse events, still consumes the click either
/// way. Returning `nil` just means "nothing here wants it," not "let it
/// fall through to the window behind me."
///
/// The actual mechanism for that is toggling `window.ignoresMouseEvents`
/// itself, continuously, based on live cursor position — `true` (pass
/// through to whatever's behind) while the cursor is outside the active
/// rect, `false` (this window handles it) while inside. Because
/// `ignoresMouseEvents = true` makes the window invisible to the event
/// system entirely, this needs BOTH a local monitor (catches movement
/// while the cursor is still "inside" this app's event stream) and a
/// global monitor (catches movement while `ignoresMouseEvents` has
/// already made this window transparent to events, at which point, from
/// the system's perspective, those events belong to whatever's now
/// topmost — which isn't this app).
@MainActor
final class WindowManager {
    private var window: IslandWindow?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private var isHoverActive = false

    private var compactSize: CGSize {
        CGSize(width: DesignTokens.MusicMetrics.compactWidth, height: DesignTokens.MusicMetrics.compactHeight)
    }
    private var expandedSize: CGSize {
        CGSize(width: DesignTokens.MusicMetrics.expandedWidth, height: DesignTokens.MusicMetrics.expandedHeight)
    }

    /// The static window canvas: max content size plus the shadow margin.
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

        startMouseTracking()
        // Correct the initial state immediately rather than waiting for
        // the first mouse-moved event — if the cursor already happens to
        // be resting over the pill when the app launches, it should be
        // interactive from frame one, not after the user first twitches
        // the mouse.
        updateClickThrough()
    }

    /// Called from `IslandRootView`'s hover handler on the same undelayed
    /// signal as the resting shadow — widens which rect counts as "active"
    /// to the full expanded card the instant a hover begins, narrows back
    /// to the small resting pill the instant it ends.
    func setHoverActive(_ active: Bool) {
        isHoverActive = active
        updateClickThrough()
    }

    private func startMouseTracking() {
        guard localMouseMonitor == nil else { return }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { [weak self] event in
            self?.updateClickThrough()
            return event // must pass the event through, not swallow it
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) { [weak self] _ in
            self?.updateClickThrough()
        }
    }

    private func updateClickThrough() {
        guard let window else { return }
        let cursor = NSEvent.mouseLocation // screen coordinates, valid regardless of which monitor fired
        let active = activeRectOnScreen(for: window)
        window.ignoresMouseEvents = !active.contains(cursor)
    }

    /// Converts whichever rect is currently active (compact or expanded,
    /// per `isHoverActive`) from top-left "canvas" coordinates (matching
    /// every other layout calculation in this codebase) into AppKit's
    /// bottom-left screen coordinate space.
    private func activeRectOnScreen(for window: NSWindow) -> NSRect {
        let size = isHoverActive ? expandedSize : compactSize
        let canvas = canvasSize
        let originInCanvas = CGPoint(x: (canvas.width - size.width) / 2, y: 0) // top-flush, centered

        let screenX = window.frame.origin.x + originInCanvas.x
        let screenY = window.frame.origin.y + (canvas.height - originInCanvas.y - size.height)
        return NSRect(x: screenX, y: screenY, width: size.width, height: size.height)
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

    deinit {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
    }
}
