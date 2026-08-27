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
/// The window itself is static (see `WindowManager`'s doc comment) — this
/// view no longer reports target sizes to anything. `isExpanded` is the
/// only signal; `MusicIslandView` (and any future activity's view) reads
/// it directly and animates its own frame/content accordingly.
struct IslandRootView: View {
    @ObservedObject var activityManager: ActivityManager

    /// Widens/narrows the window's actual clickable region — see
    /// `WindowManager.setHoverActive`. Fired on the same undelayed signal
    /// as the resting shadow (`isPrimed`), not the delayed `isExpanded`.
    var onHoverRegionChange: (Bool) -> Void = { _ in }

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
        // Always-on subtle resting shadow, strengthening the instant a
        // hover begins (isPrimed) — one continuous shadow at two
        // magnitudes, not "nothing, then a shadow."
        .shadow(
            color: isPrimed ? DesignTokens.Shadow.hoverColor : DesignTokens.Shadow.restColor,
            radius: isPrimed ? DesignTokens.Shadow.hoverRadius : DesignTokens.Shadow.restRadius,
            x: 0,
            y: isPrimed ? DesignTokens.Shadow.hoverYOffset : DesignTokens.Shadow.restYOffset
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
        // The window's clickable region widens on this exact same signal
        // (see WindowManager.setHoverActive) so it's never left too small
        // right after the cursor triggers a hover.
        isPrimed = hovering
        onHoverRegionChange(hovering)

        let delay = hovering ? AnimationTokens.hoverActivationDelay : AnimationTokens.hoverDeactivationDelay
        let workItem = DispatchWorkItem {
            // Guard against a hover-in-then-out (or vice versa) that happened
            // during the delay window — only commit if the state is still
            // what triggered this work item.
            guard isHovering == hovering else { return }

            // One transaction, one persisting view (`MusicIslandView`) —
            // every modifier driven by `isExpanded` (frame size, element
            // positions, opacities, the shape's corner radii) animates
            // together automatically. The AppKit window itself no longer
            // moves at all (see `WindowManager`'s doc comment) — this
            // SwiftUI transaction is now the ONLY animation system driving
            // the visible size, which is what guarantees everything stays
            // in lockstep.
            withAnimation(AnimationTokens.shapeMorph(isExpanding: hovering)) {
                isExpanded = hovering
            }
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
