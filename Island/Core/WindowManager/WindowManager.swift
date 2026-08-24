import AppKit
import SwiftUI

/// Responsible ONLY for window creation, positioning, visibility, and
/// display synchronization.
///
/// The window is permanently anchored to the physical notch, horizontally
/// centered on it. Expansion/collapse is driven by an explicit, animated
/// AppKit frame change to two KNOWN target sizes (compact/expanded) — not
/// by reacting to a SwiftUI-measured content size. That distinction is the
/// actual fix for the "expands from the left edge" bug: measuring content
/// size via GeometryReader/PreferenceKey only reports a view's size AFTER
/// SwiftUI has already swapped to the new (structurally different) child
/// view, which happens as a discrete jump — not a smooth interpolation —
/// well before the matchedGeometryEffect spring visually catches up. That
/// jump moved+resized the window discontinuously mid-animation, which is
/// what made the still-animating content look like it was growing from one
/// side instead of from a fixed center.
///
/// Since both target sizes are already known constants, there's no need to
/// measure anything — we drive directly to the correct centered frame,
/// using a `SpringAnimator` built from the exact same physics as the
/// SwiftUI content's spring (`AnimationTokens.shapePhysics`), instead of
/// the previous `NSAnimationContext` + fixed-duration ease curve. That
/// mismatch — a real spring on one side, a fixed ease curve on the other —
/// is what made the window and the content visibly disagree about motion.
/// The spring animator is also properly interruptible: retargeting
/// mid-flight (e.g. the user moves the mouse in and out quickly) carries
/// current position and velocity forward instead of restarting or racing
/// a second animation, which is what the old `Task.sleep`-based delay path
/// could do.
///
/// Everything about sizing/positioning below is unchanged from the
/// original — this pass only touches *how* the frame gets from A to B,
/// not what A and B are.
@MainActor
final class WindowManager {
    private var window: IslandWindow?
    private var animator: SpringAnimator?

    private let defaultCompactSize = CGSize(
        width: DesignTokens.MusicMetrics.compactWidth,
        height: DesignTokens.MusicMetrics.compactHeight
    )

    func present<Content: View>(_ rootView: Content) {
        let screen = notchScreen()
        let origin = notchOrigin(on: screen, size: defaultCompactSize)

        let panel = window ?? IslandWindow(contentRect: NSRect(origin: origin, size: defaultCompactSize))

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: defaultCompactSize)
        // Lets the content view track the window's animated frame changes
        // automatically (AppKit resizes it in step with every frame we
        // set), instead of us having to set its frame manually on every
        // intermediate animation tick.
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        window = panel

        let springAnimator = SpringAnimator(initialSize: defaultCompactSize, physics: AnimationTokens.shapePhysics)
        springAnimator.onUpdate = { [weak self, weak panel] liveSize in
            guard let self, let panel else { return }
            let origin = self.notchOrigin(on: self.notchScreen(), size: liveSize)
            panel.setFrame(NSRect(origin: origin, size: liveSize), display: true)
        }
        animator = springAnimator
    }

    /// Animates the window to `size`, centered on the notch, with its top
    /// edge always locked to the physical screen top — grows/shrinks
    /// symmetrically about that fixed horizontal center, never translating
    /// sideways, per the required behavior.
    ///
    /// `delay` lets the caller keep this in sync with
    /// `AnimationTokens.shapeMorph`: on collapse, the SwiftUI content stays
    /// full-size for `AnimationTokens.collapseShapeDelay` while it fades
    /// out, so the window must wait that same amount before shrinking —
    /// otherwise it would clip the still-full-size content. Calling this
    /// again before a previous call has settled (or before its delay has
    /// elapsed) simply redirects the same spring — see `SpringAnimator`.
    func animateToSize(_ size: CGSize, delay: TimeInterval = 0) {
        guard size.width > 0, size.height > 0 else { return }
        animator?.animate(to: size, delay: delay)
    }

    private func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func notchOrigin(on screen: NSScreen?, size: CGSize) -> NSPoint {
        guard let frame = screen?.frame else { return .zero }
        // Horizontally centered on the screen (the notch is always centered
        // on real hardware). Vertically flush with the absolute top edge of
        // the screen — not the menu bar or safe-area inset — since the
        // island's top edge is meant to visually merge with the physical
        // notch itself. Rounded to whole points so the panel doesn't sit on
        // a fractional pixel boundary.
        //
        // This is computed fresh from `size` alone (not relative to any
        // prior frame), so for any given size the result is always exactly
        // centered — the same guarantee that makes `animateToSize` grow
        // symmetrically about a fixed center rather than drifting.
        let x = (frame.midX - (size.width / 2)).rounded()
        let y = (frame.maxY - size.height).rounded()
        return NSPoint(x: x, y: y)
    }
}
