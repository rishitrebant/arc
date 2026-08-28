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

    /// Reports docking state to WindowManager so the hidden island still
    /// has a small clickable area at the top-center.
    var onDockStateChange:
        (Bool, ObjectIdentifier) -> Void = { _, _ in }

    @Namespace private var morphNamespace

    @State private var isHovering = false
    @State private var isExpanded = false
    @State private var hoverWorkItem: DispatchWorkItem?

    /// Immediate hover feedback.
    @State private var isPrimed = false

    // MARK: - Docking

    /// True while the island is tucked away at the top-center.
    @State private var isDocked = false

    /// Temporary drag amount while dragging.
    @State private var dockDragOffset: CGFloat = 0

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
                .offset(
                    y:
                        isDocked
                            ? 0
                            : dockDragOffset
                )
                .opacity(
                    isDocked
                        ? 0
                        : 1
                )

            } else {

                Color.clear
                    .frame(
                        width:
                            compactSize.width,

                        height:
                            compactSize.height
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

        // ---------------------------------------------------------
        // IMPORTANT:
        //
        // Even when the island is invisible, this view remains
        // hit-testable so the user can click/drag it back.
        // ---------------------------------------------------------

        .contentShape(
            Rectangle()
        )

        // ---------------------------------------------------------
        // EXISTING SHADOW
        // ---------------------------------------------------------

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
            value:
                isPrimed
        )

        // ---------------------------------------------------------
        // EXISTING HOVER
        // ---------------------------------------------------------

        .onHover { hovering in

            handleHover(
                hovering
            )
        }

        // ---------------------------------------------------------
        // CLICK TO UNDOCK
        //
        // Single click works.
        //
        // A double click also contains a click, so this is enough
        // for the requested "single OR double click" behaviour.
        // ---------------------------------------------------------

        .onTapGesture {

            guard isDocked else {
                return
            }

            undock()
        }

        // ---------------------------------------------------------
        // DRAG TO DOCK / UNDOCK
        // ---------------------------------------------------------

        .simultaneousGesture(
            DragGesture(
                minimumDistance: 4
            )
            .onChanged { value in

                handleDockDrag(
                    value.translation.height
                )
            }
            .onEnded { value in

                handleDockDragEnded(
                    value.translation.height
                )
            }
        )
    }

    // MARK: - Hover

    private func handleHover(
        _ hovering: Bool
    ) {

        // Never expand while docked.
        guard !isDocked else {
            return
        }

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

                // =====================================================
                // YOUR ORIGINAL MORPH ANIMATION.
                //
                // COMPLETELY UNTOUCHED.
                // =====================================================

                withAnimation(
                    AnimationTokens.shapeMorph(
                        isExpanding:
                            hovering
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

    // MARK: - Dock Drag

    private func handleDockDrag(
        _ translation: CGFloat
    ) {

        // ---------------------------------------------------------
        // ALREADY DOCKED
        //
        // Drag DOWN to bring it back.
        // ---------------------------------------------------------

        if isDocked {

            if translation > 0 {

                dockDragOffset =
                    min(
                        translation,
                        70
                    )
            }

            return
        }

        // ---------------------------------------------------------
        // NORMAL
        //
        // Drag UP toward the notch.
        // ---------------------------------------------------------

        if translation < 0 {

            dockDragOffset =
                max(
                    translation,
                    -100
                )
        }
    }

    // MARK: - Dock Drag End

    private func handleDockDragEnded(
        _ translation: CGFloat
    ) {

        // ---------------------------------------------------------
        // DOCKED → NORMAL
        // ---------------------------------------------------------

        if isDocked {

            if translation > 20 {

                undock()

            } else {

                // No sufficient downward drag.
                dockDragOffset =
                    0
            }

            return
        }

        // ---------------------------------------------------------
        // NORMAL → DOCKED
        // ---------------------------------------------------------

        if translation < -35 {

            dock()

        } else {

            // Not far enough.
            dockDragOffset =
                0
        }
    }

    // MARK: - Dock

    private func dock() {

        hoverWorkItem?.cancel()

        hoverWorkItem =
            nil

        isHovering =
            false

        isPrimed =
            false

        // Docking is always from compact state.
        isExpanded =
            false

        dockDragOffset =
            0

        // ---------------------------------------------------------
        // NO SPRING.
        // NO SCALE.
        // NO FADE.
        //
        // It simply disappears.
        // ---------------------------------------------------------

        isDocked =
            true

        onDockStateChange(
            true,
            screenID
        )
    }

    // MARK: - Undock

    private func undock() {

        // Already visible.
        guard isDocked else {
            return
        }

        // Make it visible immediately.
        isDocked =
            false

        dockDragOffset =
            0

        onDockStateChange(
            false,
            screenID
        )

        // Don't accidentally trigger an expansion immediately.
        isHovering =
            false

        isExpanded =
            false

        isPrimed =
            false
    }
}
