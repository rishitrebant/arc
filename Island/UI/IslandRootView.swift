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

    // True only while the pointer is over the Island itself.
    // This is separate from the picker state because moving into the
    // picker necessarily makes the Island's hover region report false.
    @State private var isPointerOverIsland = false

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

    /// While one activity hands the island straight to another, this
    /// black pill sits underneath and morphs from the old pill's size to
    /// the new one's, so the surface itself never disappears — only the
    /// content on it cross-fades.
    @State private var showHandoverBackdrop = false
    @State private var handoverBackdropSize: CGSize = .zero
    @State private var handoverWorkItem: DispatchWorkItem?

    /// Which half of a shared pill the cursor is over.
    @State private var hoverSide: EarSide = .leading

    /// The pill's size one change ago — where a morph starts from.
    @State private var previousVisibleSize: CGSize = .zero

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

    /// Two activities are sharing the notch as one even pill — owner on
    /// the left, the second on the right.
    private var isSplitMode: Bool {
        !isExpanded
            && !isDocked
            && renderedActivity != nil
            && activityManager.splitCompactSize != nil
    }

    /// The activity whose view is on screen: normally the owner, but
    /// when the cursor is on the second half of a shared pill and it
    /// expands, that second activity takes the island.
    private var presentedActivity: AnyActivity? {

        if isExpanded,
           activityManager.expandsSecondary,
           let secondary = activityManager.secondaryActivity {
            return secondary
        }

        return renderedActivity
    }

    /// The size of the pill actually on screen right now.
    private var visibleSize: CGSize {

        if isSplitMode, let size = activityManager.splitCompactSize {
            return size
        }

        guard let activity = presentedActivity else {
            return compactSize
        }

        return isExpanded
            ? activity.expandedSize
            : activity.compactSize
    }

    /// Scale that squeezes the current pill down to the physical notch
    /// (`notchWidth` × `collapsedNotchHeight`) — what every activity
    /// grows out of and shrinks back into, whatever its own size.
    private var notchScale: CGSize {

        let size = visibleSize

        return CGSize(
            width: min(
                1,
                max(0.001, DesignTokens.FileDropMetrics.notchWidth / max(size.width, 1))
            ),
            height: min(
                1,
                max(0.001, DesignTokens.Shape.collapsedNotchHeight / max(size.height, 1))
            )
        )
    }

    // MARK: - Side bubbles

    /// A second activity as a small rounded square just past the pill —
    /// only when the owner can't share the notch as one even pill (a
    /// charger or Bluetooth moment, say, with a timer running).
    private var sideBubbles: some View {

        typealias Bubble = DesignTokens.BubbleMetrics

        let centerX = visibleSize.width / 2 + Bubble.pillGap + Bubble.side / 2

        return ZStack(alignment: .top) {

            if !isExpanded,
               !isDocked,
               renderedActivity != nil,
               activityManager.splitCompactSize == nil,
               let bubble = activityManager.secondaryActivity?.minimalView {

                bubble
                    .offset(x: centerX, y: Bubble.topInset)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(
            width: DesignTokens.sharedCanvasSize.width,
            height: DesignTokens.FileDropMetrics.notchKeepClearHeight,
            alignment: .top
        )
        .allowsHitTesting(false)
        .animation(
            AnimationTokens.ownershipChange,
            value: activityManager.secondaryActivity?.id
        )
    }

    var body: some View {

        Group {

            if let activity =
                renderedActivity {

                ZStack(alignment: .top) {

                    // The black surface. It morphs between sizes (single
                    // pill ↔ shared pill ↔ expanded) on the same spring
                    // as everything else while the content on it
                    // cross-fades.
                    if showHandoverBackdrop {

                        IslandShape(
                            topRadius: isExpanded
                                ? DesignTokens.Shape.expandedTopRadius
                                : DesignTokens.Shape.compactTopRadius,
                            bottomRadius: isExpanded
                                ? DesignTokens.Shape.expandedBottomRadius
                                : DesignTokens.Shape.compactBottomRadius
                        )
                        .fill(DesignTokens.Color.islandBackground)
                        .frame(
                            width: handoverBackdropSize.width,
                            height: handoverBackdropSize.height
                        )
                        .allowsHitTesting(false)
                    }

                    if isSplitMode,
                       let earWidth = activityManager.splitEarWidth,
                       let leading = activityManager.ownedActivity?.earView(side: .leading),
                       let trailing = activityManager.secondaryActivity?.earView(side: .trailing) {

                        SplitIslandContent(
                            leading: leading,
                            trailing: trailing,
                            earWidth: earWidth
                        )
                        .id("split")
                        .transition(.opacity)

                    } else {

                        let shown = presentedActivity ?? activity

                        shown.islandView(
                            isExpanded:
                                isExpanded
                        )
                        .id(shown.id)
                        .transition(.opacity)
                    }
                }
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
        // The island grows/shrinks from the notch (top-center),
        // matching the compact<->expand morph's anchor, instead of
        // popping in at full height from the center of the screen.
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
                    : notchScale.width,

            // Every activity, compact or expanded, grows out of and
            // shrinks back into the notch itself (179 wide, 29 tall) —
            // not a flat line, and not just along one axis.
            y:
                isPresentationVisible
                    ? 1
                    : notchScale.height,

            anchor:
                .top
        )

        .animation(
            .easeOut(
                duration:
                    presentationAnimationDuration
            ),

            value:
                isPresentationVisible
        )

        // Detached bubbles beside the island. Deliberately OUTSIDE the
        // notch scale above, so they don't squash with the pill.
        .overlay(alignment: .top) {
            sideBubbles
        }

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

        // Only the visible pill is hoverable/clickable — not the whole
        // fixed canvas the activity views lay themselves out in.
        .contentShape(
            VisibleIslandShape(size: visibleSize)
        )

        // ---------------------------------------------------------
        // EXISTING SHADOW
        // ---------------------------------------------------------

        // Two layers, like Apple's own floating surfaces: a large soft
        // ambient shadow that grows as the island opens, plus a tight
        // contact shadow that keeps its edge crisp.
        .shadow(
            color:
                isExpanded
                    ? DesignTokens.Shadow.expandedColor
                    : (
                        isPrimed
                            ? DesignTokens.Shadow.hoverColor
                            : DesignTokens.Shadow.restColor
                    ),

            radius:
                isExpanded
                    ? DesignTokens.Shadow.expandedRadius
                    : (
                        isPrimed
                            ? DesignTokens.Shadow.hoverRadius
                            : DesignTokens.Shadow.restRadius
                    ),

            x:
                0,

            y:
                isExpanded
                    ? DesignTokens.Shadow.expandedYOffset
                    : (
                        isPrimed
                            ? DesignTokens.Shadow.hoverYOffset
                            : DesignTokens.Shadow.restYOffset
                    )
        )

        .shadow(
            color:
                DesignTokens.Shadow.contactColor,

            radius:
                DesignTokens.Shadow.contactRadius,

            x:
                0,

            y:
                DesignTokens.Shadow.contactYOffset
        )

        .animation(
            AnimationTokens.hoverPrimeTransition,
            value:
                isPrimed
        )

        .animation(
            AnimationTokens.shapeSpring,
            value:
                isExpanded
        )

        // ---------------------------------------------------------
        // EXISTING HOVER
        // ---------------------------------------------------------

        // Only used to know WHICH half of a shared pill the cursor is on
        // — whether to expand at all is `WindowManager`'s call below.
        .onContinuousHover { phase in

            if case .active(let point) = phase {
                hoverSide = point.x < visibleSize.width / 2
                    ? .leading
                    : .trailing
            }
        }

        .onChange(of: visibleSize) { old, new in

            previousVisibleSize = old

            // A shared pill's width can change while it's up (the timer
            // passing an hour) — keep the surface under it in step.
            if isSplitMode, showHandoverBackdrop {
                withAnimation(AnimationTokens.shapeSpring) {
                    handoverBackdropSize = new
                }
            }
        }

        // Going into / out of a shared pill (or into an expanded panel
        // from one) is a morph of the surface, not a pop.
        .onChange(of: isSplitMode) { _, _ in
            morphSurface()
        }

        // Hover comes from `WindowManager`'s geometry, not SwiftUI's
        // `.onHover` (see `WindowManager.activeScreenID`), so the hover
        // area is exactly the visible island.
        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandHoverChanged
            )
        ) { note in

            guard
                let id = note.userInfo?["screenID"] as? ObjectIdentifier,
                id == screenID,
                let hovering = note.userInfo?["hovering"] as? Bool
            else {
                return
            }

            handleHover(
                hovering
            )
        }

        // Tells `WindowManager` what's actually on screen, so its
        // hover/click region is compact-sized whenever the island is
        // compact. Also posts once on appear — that first post is how
        // `WindowManager` knows this view reports at all (if it never
        // does, `WindowManager` falls back to its original logic).
        .onAppear {

            NotificationCenter.default.post(
                name: .islandExpandedStateChanged,
                object: nil,
                userInfo: [
                    "screenID": screenID,
                    "expanded": isExpanded
                ]
            )
        }

        .onChange(of: isExpanded) { _, expanded in

            if !expanded {
                activityManager.expandsSecondary = false
            }

            // Only opening is felt — closing (hover-off) is silent.
            if expanded, renderedActivity != nil {
                Haptics.open()
            }

            NotificationCenter.default.post(
                name: .islandExpandedStateChanged,
                object: nil,
                userInfo: [
                    "screenID": screenID,
                    "expanded": expanded
                ]
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

            // The picker can disappear for two reasons:
            // 1. the click was on the Island/menu interaction itself
            // 2. the user clicked somewhere outside both surfaces.
            //
            // Only the second case should compact the Island.
            guard !isPointerOverIsland else {
                return
            }

            hoverWorkItem?.cancel()
            hoverWorkItem = nil

            isHovering = false
            isPrimed = false

            withAnimation(
                AnimationTokens.shapeMorph(
                    isExpanding: false
                )
            ) {
                isExpanded = false
            }
        }

        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandRequestCollapse
            )
        ) { _ in

            // Per direct request: clicking anywhere else on screen
            // should collapse the expanded island. Reuses the exact
            // same collapse logic as the output-picker-dismiss case
            // right above — same reasoning applies here too.
            hoverWorkItem?.cancel()
            hoverWorkItem = nil

            isHovering = false
            isPrimed = false

            withAnimation(
                AnimationTokens.shapeMorph(
                    isExpanding: false
                )
            ) {
                isExpanded = false
            }
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

            // Nothing on the island: a tap on the notch opens the
            // launcher (now playing, timers).
            if renderedActivity == nil {

                NotificationCenter.default.post(
                    name: .islandOpenLauncher,
                    object: nil
                )

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

                    // Nothing left to be expanded — otherwise the hover
                    // region stays expanded-sized around an empty notch.
                    hoverWorkItem?.cancel()
                    hoverWorkItem = nil
                    isHovering = false
                    isPrimed = false
                    isExpanded = false
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

        // ---------------------------------------------------------
        // HANDOVER
        //
        // One activity taking the island straight from another never
        // collapses into the notch and reopens: the pill morphs to the
        // new size while the content cross-fades.
        // ---------------------------------------------------------

        Haptics.open()

        if renderedActivity != nil,
           isPresentationVisible,
           !isDocked {

            handoverWorkItem?.cancel()

            handoverBackdropSize = visibleSize
            showHandoverBackdrop = true

            withAnimation(AnimationTokens.ownershipChange) {

                renderedActivity = newActivity

                handoverBackdropSize = isExpanded
                    ? newActivity.expandedSize
                    : newActivity.compactSize
            }

            let work = DispatchWorkItem {
                showHandoverBackdrop = false
            }

            handoverWorkItem = work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.5,
                execute: work
            )

            return
        }

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

    // MARK: - Surface morph

    /// Starts the black surface at the size the island WAS and springs it
    /// to the size it IS now, so layout changes read as one shape
    /// reshaping instead of one view swapping for another.
    private func morphSurface() {

        handoverWorkItem?.cancel()

        var instant = Transaction()
        instant.disablesAnimations = true

        withTransaction(instant) {
            handoverBackdropSize = previousVisibleSize
            showHandoverBackdrop = true
        }

        DispatchQueue.main.async {
            withAnimation(AnimationTokens.shapeSpring) {
                handoverBackdropSize = visibleSize
            }
        }

        let work = DispatchWorkItem {
            // A shared pill keeps its surface; everything else is drawn
            // by the activity itself once the morph has settled.
            if !isSplitMode {
                showHandoverBackdrop = false
            }
        }

        handoverWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.6,
            execute: work
        )
    }

    // MARK: - Hover

    private func handleHover(
        _ hovering: Bool
    ) {

        // Always record whether the pointer is over the actual Island.
        // This must happen before the picker guard below.
        isPointerOverIsland = hovering

        // Never expand while docked.
        guard !isDocked else {
            return
        }

        // Nothing is on the island, so there is nothing to expand —
        // without this an invisible island "expanded" on hover and
        // inflated the hover region around the notch.
        guard renderedActivity != nil else {
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

                if hovering {
                    activityManager.expandsSecondary =
                        isSplitMode && hoverSide == .trailing
                }

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

        activityManager.expandsSecondary =
            isSplitMode && hoverSide == .trailing

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
        // Collapse the presentation scale back down to the notch
        // (opacity is already snapping to 0 via `isDocked`, so this
        // isn't visible) so that undocking has a collapsed state to
        // grow back out from, matching ownership enter/exit and
        // startup.
        // ---------------------------------------------------------

        isPresentationVisible =
            false

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
        // The island was still rendered while docked, collapsed
        // to the notch (see `dock()`).
        //
        // Reveal it (opacity/offset become visible immediately),
        // then grow it back out from the notch on the next
        // main-loop turn — same as ownership ENTER and startup —
        // so undocking reads as one continuous surface attached
        // to the notch rather than a separate snap-into-place.
        // ---------------------------------------------------------

        presentationWorkItem?.cancel()
        presentationWorkItem = nil

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
}

/// Hit-testing shape for the island: just the visible pill, centred at
/// the top of whatever frame it's applied to.
private struct VisibleIslandShape: Shape {

    var size: CGSize

    func path(in rect: CGRect) -> Path {
        Path(
            CGRect(
                x: rect.midX - size.width / 2,
                y: rect.minY,
                width: size.width,
                height: size.height
            )
        )
    }
}
