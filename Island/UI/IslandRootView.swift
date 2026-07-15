import SwiftUI

/// Carries the root content's measured size up to `WindowManager`.
struct IslandSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

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
struct IslandRootView: View {
    @ObservedObject var activityManager: ActivityManager

    /// Reports the current content size up to WindowManager so the panel's
    /// hit-testing frame stays in sync with the animated SwiftUI content.
    /// WindowManager owns positioning; this view only ever reports size.
    var onSizeChange: (CGSize) -> Void = { _ in }

    /// Shared across whichever activity's compact/expanded views are on
    /// screen (via `islandNamespace` in the environment) so the island
    /// body, artwork, and waveform can `matchedGeometryEffect` between
    /// them — one continuous shape changing size, not one view replacing
    /// another.
    @Namespace private var morphNamespace

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var hoverWorkItem: DispatchWorkItem?

    var body: some View {
        Group {
            if let activity = activityManager.ownedActivity {
                Group {
                    if isExpanded {
                        activity.expandedView()
                    } else {
                        activity.compactView()
                    }
                }
            } else {
                Color.clear.frame(
                    width: DesignTokens.MusicMetrics.compactWidth,
                    height: DesignTokens.MusicMetrics.compactHeight
                )
            }
        }
        .environment(\.islandNamespace, morphNamespace)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: IslandSizePreferenceKey.self, value: proxy.size)
            }
        )
        .onPreferenceChange(IslandSizePreferenceKey.self) { size in
            onSizeChange(size)
        }
        .animation(AnimationTokens.ownershipChange, value: activityManager.ownedActivity?.id)
        .onHover { hovering in
            handleHover(hovering)
        }
    }

    private func handleHover(_ hovering: Bool) {
        isHovering = hovering
        hoverWorkItem?.cancel()

        let delay = hovering ? AnimationTokens.hoverActivationDelay : AnimationTokens.hoverDeactivationDelay
        let workItem = DispatchWorkItem {
            // Guard against a hover-in-then-out (or vice versa) that happened
            // during the delay window — only commit if the state is still
            // what triggered this work item.
            guard isHovering == hovering else { return }
            // One explicit transaction covers the matchedGeometryEffect
            // frame/position interpolation AND the IslandShape corner-radius
            // interpolation together, so they move in lockstep rather than
            // as two independently-timed animations.
            withAnimation(AnimationTokens.shapeMorph(isExpanding: hovering)) {
                isExpanded = hovering
            }
        }
        hoverWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}
