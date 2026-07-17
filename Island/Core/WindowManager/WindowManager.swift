import AppKit
import SwiftUI
import QuartzCore

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
/// measure anything — we can just animate directly to the correct centered
/// frame, in lockstep with the SwiftUI spring.
@MainActor
final class WindowManager {
    private var window: IslandWindow?

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
        // automatically (AppKit resizes it in step with the window
        // animator), instead of us having to set its frame manually on
        // every intermediate animation tick.
        hosting.autoresizingMask = [.width, .height]

        panel.contentView = hosting
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        window = panel
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
    /// otherwise it would clip the still-full-size content.
    func animateToSize(_ size: CGSize, delay: TimeInterval = 0) {
        guard let window, size.width > 0, size.height > 0 else { return }

        let targetOrigin = notchOrigin(on: notchScreen(), size: size)
        let targetFrame = NSRect(origin: targetOrigin, size: size)

        if delay > 0 {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay))

                await NSAnimationContext.runAnimationGroup { context in
                    context.duration = AnimationTokens.shapeDuration
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    window.animator().setFrame(targetFrame, display: true)
                }
            }
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = AnimationTokens.shapeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().setFrame(targetFrame, display: true)
            }
        }
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
