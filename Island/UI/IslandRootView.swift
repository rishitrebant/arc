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

    // Keeps the island expanded while the output-device picker is open.
    @State private var isOutputPickerOpen = false

    // MARK: - Docking

    /// True while the island is tucked away at the top-center.
    @State private var isDocked = false

    /// Temporary drag amount while dragging.
    @State private var dockDragOffset: CGFloat = 0

    // MARK: - Enter / Exit Animation

    /// The activity currently being rendered.
    ///
    /// This deliberately stays alive for the duration of the exit
    /// animation. That prevents SwiftUI from destroying the island
    /// halfway through the animation and causing the old flicker/glitch.
    @State private var renderedActivity: AnyActivity?

    /// Controls the horizontal "emerge from centre" animation.
    ///
    /// false = collapsed into the centre
    /// true  = full island width
    @State private var isPresentationVisible = false

    /// Cancels a pending exit if another activity arrives during it.
    @State private var presentationWorkItem: DispatchWorkItem?

    /// Duration for the very small horizontal enter/exit animation.
    ///
    /// This is intentionally separate from the existing morph animation.
    private let presentationAnimationDuration:
        TimeInterval = 0.18

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
                renderedActivity {

                activity.islandView(
                    isExpanded:
                        isExpanded
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

        // ---------------------------------------------------------
        // EXISTING OWNERSHIP ANIMATION
        //
        // LEFT COMPLETELY INTACT.
        // ---------------------------------------------------------

        .animation(
            AnimationTokens.ownershipChange,
            value:
                activityManager
                    .ownedActivity?
                    .id
        )

        // ---------------------------------------------------------
        // ENTER / EXIT SCALE
        //
        // This is the ONLY animation added for the new feature.
        //
        // The island grows/shrinks horizontally around its exact
        // centre.
        //
        // No opacity animation.
        // No layout animation.
        // No transition.
        // No changing frame size.
        //
        // This prevents the previous fade-out glitches.
        // ---------------------------------------------------------

        .scaleEffect(
            x:
                isPresentationVisible
                    ? 1
                    : 0.001,

            y:
                1,

            anchor:
                .center
        )

        .animation(
            .easeOut(
                duration:
                    presentationAnimationDuration
            ),

            value:
                isPresentationVisible
        )

        // ---------------------------------------------------------
        // IMPORTANT:
        //
        // Watch ownership separately so we can keep the old island
        // mounted while it shrinks to the centre.
        // ---------------------------------------------------------

        .onAppear {

            syncInitialPresentation()
        }

        .onChange(
            of:
                activityManager
                    .ownedActivity?
                    .id
        ) { _, _ in

            handleOwnershipChange()
        }

        // ---------------------------------------------------------
        // CLICK THROUGH REGION
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

            x:
                0,

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

        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandOutputPickerWillPresent
            )
        ) { _ in

            isOutputPickerOpen = true

            hoverWorkItem?.cancel()
        }

        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandOutputPickerDidDismiss
            )
        ) { _ in

            isOutputPickerOpen = false
        }

        // ---------------------------------------------------------
        // CLICK TO EXPAND / UNDOCK
        // ---------------------------------------------------------

        .onTapGesture {

            // A tap on the docked island brings it back immediately.
            if isDocked {

                undock()

                return
            }

            // A tap on the compact island bypasses the hover delay.
            if !isExpanded {

                expandImmediately()
            }
        }

        // ---------------------------------------------------------
        // DRAG TO DOCK / UNDOCK
        // ---------------------------------------------------------

        .simultaneousGesture(

            DragGesture(
                minimumDistance:
                    4
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

    // MARK: - Enter / Exit

    /// Establishes the initial activity without animating from an
    /// empty state. This prevents the island from appearing late when
    /// the app first launches.
    private func syncInitialPresentation() {

        presentationWorkItem?.cancel()
        presentationWorkItem = nil

        renderedActivity =
            activityManager.ownedActivity

        // A docked island must remain visually hidden.

        if isDocked {

            isPresentationVisible =
                false

            return
        }

        // ---------------------------------------------------------
        // Startup:
        //
        // The island starts at the centre and spreads outward.
        //
        // We intentionally trigger this on the next main-loop turn
        // so SwiftUI has already laid out the view at scale 0.001.
        // That avoids the first-frame snap/glitch.
        // ---------------------------------------------------------

        guard renderedActivity != nil else {

            isPresentationVisible =
                false

            return
        }

        isPresentationVisible =
            false

        DispatchQueue.main.async {

            guard
                !isDocked,
                renderedActivity != nil
            else {
                return
            }

            isPresentationVisible =
                true
        }
    }

    /// Handles a change in island ownership.
    ///
    /// New activity:
    ///     centre → sides
    ///
    /// No activity:
    ///     sides → centre → removed
    private func handleOwnershipChange() {

        presentationWorkItem?.cancel()
        presentationWorkItem = nil

        guard
            let newActivity =
                activityManager.ownedActivity
        else {

            // ---------------------------------------------------------
            // EXIT
            //
            // Keep `renderedActivity` alive.
            //
            // First shrink it to the centre.
            // Only AFTER the animation completes do we remove it.
            // ---------------------------------------------------------

            isPresentationVisible =
                false

            let workItem =
                DispatchWorkItem { [self] in

                    // Only remove the rendered activity if there still
                    // isn't a new owner waiting for the island.

                    guard
                        activityManager
                            .ownedActivity
                        == nil
                    else {
                        return
                    }

                    renderedActivity =
                        nil
                }

            presentationWorkItem =
                workItem

            DispatchQueue.main.asyncAfter(
                deadline:
                    .now()
                    + presentationAnimationDuration,

                execute:
                    workItem
            )

            return
        }

        // ---------------------------------------------------------
        // NEW ACTIVITY
        // ---------------------------------------------------------

        renderedActivity =
            newActivity

        // If currently docked, don't visually enter yet.
        // Undocking will reveal it normally.
        guard !isDocked else {

            isPresentationVisible =
                false

            return
        }

        // ---------------------------------------------------------
        // ENTER
        //
        // Start completely collapsed.
        // Then spread horizontally from the centre.
        // ---------------------------------------------------------

        isPresentationVisible =
            false

        DispatchQueue.main.async {

            guard
                !isDocked,
                renderedActivity?.id
                    == newActivity.id
            else {
                return
            }

            isPresentationVisible =
                true
        }
    }

    // MARK: - Hover

    private func handleHover(
        _ hovering: Bool
    ) {

        // Never expand while docked.
        guard !isDocked else {
            return
        }

        // The native/system-style output picker is a separate popover.
        // Moving the pointer into it temporarily leaves the island's
        // hover region, but the island must stay expanded.
        if isOutputPickerOpen && !hovering {
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
                // EXISTING MORPH ANIMATION.
                //
                // DO NOT CHANGE.
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
                .now()
                + delay,

            execute:
                workItem
        )
    }

    // MARK: - Immediate Tap Expansion

    private func expandImmediately() {

        // Cancel delayed hover expansion.
        hoverWorkItem?.cancel()
        hoverWorkItem = nil

        // Same morph animation as hover.
        withAnimation(
            AnimationTokens.shapeMorph(
                isExpanding:
                    true
            )
        ) {

            isExpanded =
                true
        }
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

            dockDragOffset =
                0
        }
    }

    // MARK: - Dock

    private func dock() {

        hoverWorkItem?.cancel()
        hoverWorkItem = nil

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
        // EXISTING DOCK BEHAVIOUR.
        //
        // NO ENTER/EXIT ANIMATION HERE.
        //
        // Docking is deliberately kept separate from activity
        // ownership animation.
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

        // ---------------------------------------------------------
        // The island was still rendered while docked.
        //
        // Bring it back at full size exactly as before.
        //
        // No new entrance animation is applied to undocking.
        // ---------------------------------------------------------

        isPresentationVisible =
            true
    }
}
