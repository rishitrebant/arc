import SwiftUI

/// The single view hosted by each monitor's IslandWindow.
///
/// Every display gets its own instance of this view, meaning each island
/// owns its own hover/expanded state. Hovering the island on Monitor 2
/// therefore expands only Monitor 2's island.
struct IslandRootView: View {

    @ObservedObject var activityManager: ActivityManager

    /// Identifies which physical display owns this island.
    let screenID: ObjectIdentifier

    /// Reports the immediate hover state to WindowManager so the actual
    /// AppKit click-through region can widen/narrow alongside the visual
    /// hover state.
    var onHoverRegionChange:
        (Bool, ObjectIdentifier) -> Void = { _, _ in }

    @Namespace private var morphNamespace

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var hoverWorkItem: DispatchWorkItem?

    /// Immediate hover feedback.
    @State private var isPrimed = false

    private var compactSize: CGSize {
        CGSize(
            width:
                DesignTokens.MusicMetrics.compactWidth,
            height:
                DesignTokens.MusicMetrics.compactHeight
        )
    }

    var body: some View {

        Group {

            if let activity =
                activityManager.ownedActivity {

                activity.islandView(
                    isExpanded: isExpanded
                )

            } else {

                Color.clear
                    .frame(
                        width: compactSize.width,
                        height: compactSize.height
                    )
            }
        }

        .environment(
            \.islandNamespace,
            morphNamespace
        )

        .animation(
            AnimationTokens.ownershipChange,
            value:
                activityManager
                    .ownedActivity?
                    .id
        )

        .shadow(
            color:
                isPrimed
                    ? DesignTokens.Shadow.hoverColor
                    : DesignTokens.Shadow.restColor,

            radius:
                isPrimed
                    ? DesignTokens.Shadow.hoverRadius
                    : DesignTokens.Shadow.restRadius,

            x: 0,

            y:
                isPrimed
                    ? DesignTokens.Shadow.hoverYOffset
                    : DesignTokens.Shadow.restYOffset
        )

        .animation(
            AnimationTokens.hoverPrimeTransition,
            value: isPrimed
        )

        .onHover { hovering in
            handleHover(
                hovering
            )
        }
    }

    // MARK: - Hover

    private func handleHover(
        _ hovering: Bool
    ) {

        isHovering =
            hovering

        hoverWorkItem?.cancel()

        // Immediate visual acknowledgement.
        isPrimed =
            hovering

        // Tell WindowManager which monitor is active.
        onHoverRegionChange(
            hovering,
            screenID
        )

        let delay =
            hovering
                ? AnimationTokens.hoverActivationDelay
                : AnimationTokens.hoverDeactivationDelay

        let workItem =
            DispatchWorkItem {

                guard
                    isHovering == hovering
                else {
                    return
                }

                withAnimation(
                    AnimationTokens.shapeMorph(
                        isExpanding: hovering
                    )
                ) {
                    isExpanded =
                        hovering
                }
            }

        hoverWorkItem =
            workItem

        DispatchQueue.main.asyncAfter(
            deadline:
                .now() + delay,
            execute:
                workItem
        )
    }
}
