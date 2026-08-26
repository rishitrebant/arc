import SwiftUI

/// The single view hosted by `WindowManager`. Owns hover-delay arbitration
/// and compact <-> expanded switching for whichever activity currently owns
/// the island — per Hover Philosophy: "expansion must feel intentional,
/// never accidental," and per Motion Philosophy: "every animation begins
/// and ends at the notch."
///
/// This logic is intentionally generic (not Music-specific) since every
/// future activity (Calls, Bluetooth, AirDrop...) needs the same hover
/// behavior — duplicating it per-activity would violate the "no duplicated
/// business logic" rule in the Engineering Constitution.
///
/// NOTE on `onSizeChange`: this now reports a KNOWN target size (compact or
/// expanded), not a measured one. It used to report the content's actual
/// rendered size via GeometryReader/PreferenceKey, but that measurement
/// jumps discretely the instant SwiftUI swaps to the other view — it can't
/// reflect the smooth in-between sizes of an ongoing spring animation. That
/// jump was the root cause of the window appearing to grow from one edge
/// instead of from a fixed center. Since both target sizes are fixed
/// constants, there's nothing to measure — we just tell WindowManager
/// exactly what to animate to and when. The Music-specific size constants
/// here are a known, called-out compromise: a future activity with
/// different compact/expanded sizes would need this generalized (e.g. via
/// the `Activity` protocol exposing its own sizes) rather than hardcoded.
struct IslandRootView: View {
    @ObservedObject var activityManager: ActivityManager

    /// Reports the target size to animate to, and how long to delay before
    /// starting (kept in sync with `AnimationTokens.shapeMorph`'s own
    /// delay so the window and the SwiftUI content move in lockstep).
    var onSizeChange: (CGSize, TimeInterval) -> Void = { _, _ in }

    /// No longer used by Music (`MusicIslandView` is a single persistent
    /// view now, not two views needing to be bridged — see its doc
    /// comment). Kept in the environment for a future activity that
    /// genuinely does need to morph BETWEEN two different view hierarchies
    /// (e.g. an ownership handoff from Music to a Call), which is a
    /// different situation than one activity's own compact↔expanded state.
    @Namespace private var morphNamespace

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var hoverWorkItem: DispatchWorkItem?

    /// True the instant a hover starts, false the instant it ends — no
    /// delay either direction. Deliberately separate from `isExpanded`,
    /// which only flips after `hoverActivationDelay`/
    /// `hoverDeactivationDelay`. This is what drives the "noticed you"
    /// shadow: it has to move independently of (and ahead of) the actual
    /// expand, or there's nothing distinguishing "registered your hover"
    /// from "committing to expand" — they'd just be the same delayed event.
    @State private var isPrimed = false

    private var compactSize: CGSize {
        CGSize(width: DesignTokens.MusicMetrics.compactWidth, height: DesignTokens.MusicMetrics.compactHeight)
    }
    private var expandedSize: CGSize {
        CGSize(width: DesignTokens.MusicMetrics.expandedWidth, height: DesignTokens.MusicMetrics.expandedHeight)
    }

    var body: some View {
        Group {
            if let activity = activityManager.ownedActivity {
                // ONE call, not a branch between two different views. This
                // is the actual fix for the left-side-grows-first bug — see
                // MusicIslandView's doc comment for the full explanation.
                activity.islandView(isExpanded: isExpanded)
            } else {
                Color.clear.frame(width: compactSize.width, height: compactSize.height)
            }
        }
        .environment(\.islandNamespace, morphNamespace)
        .animation(AnimationTokens.ownershipChange, value: activityManager.ownedActivity?.id)
        // The instant "noticed you" affordance — animates on its own the
        // moment `isPrimed` changes, completely independent of the
        // expand/collapse spring below. Color/radius/y are collapsed to
        // zero at rest so there's nothing to see (and nothing to
        // mis-render) until a hover actually begins.
        .shadow(
            color: isPrimed ? DesignTokens.Shadow.hoverColor : .clear,
            radius: isPrimed ? DesignTokens.Shadow.hoverRadius : 0,
            x: 0,
            y: isPrimed ? DesignTokens.Shadow.hoverYOffset : 0
        )
        .animation(AnimationTokens.hoverPrimeTransition, value: isPrimed)
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverWorkItem?.cancel()

        // Fires immediately, no delay — this is the whole point. The
        // shadow has to lead the expand, not share its timing with it.
        isPrimed = hovering

        let delay = hovering ? AnimationTokens.hoverActivationDelay : AnimationTokens.hoverDeactivationDelay
        let workItem = DispatchWorkItem {
            // Guard against a hover-in-then-out (or vice versa) that happened
            // during the delay window — only commit if the state is still
            // what triggered this work item.
            guard isHovering == hovering else { return }

            // One transaction, one persisting view (`MusicIslandView`) —
            // every modifier driven by `isExpanded` (frame size, element
            // positions, opacities, the shape's corner radii) animates
            // together automatically, with nothing left to fall out of
            // sync.
            withAnimation(AnimationTokens.shapeMorph(isExpanding: hovering)) {
                isExpanded = hovering
            }

            // Fired at the exact same moment as the SwiftUI animation above,
            // with the exact same delay-on-collapse, so the window frame
            // and the visible content move in lockstep instead of the
            // window jumping ahead.
            let targetSize = hovering ? expandedSize : compactSize
            let sizeDelay = hovering ? 0 : AnimationTokens.collapseShapeDelay
            onSizeChange(targetSize, sizeDelay)
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
