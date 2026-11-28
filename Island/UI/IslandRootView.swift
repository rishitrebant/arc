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

    @AppStorage(AppSettings.Key.notchGlowEnabled)
    private var notchGlowEnabled = AppSettings.Default.notchGlowEnabled

    @AppStorage(AppSettings.Key.notchGlowColor)
    private var notchGlowColor = AppSettings.Default.notchGlowColor

    @AppStorage(AppSettings.Key.notchGlowIntensity)
    private var notchGlowIntensity = AppSettings.Default.notchGlowIntensity

    @AppStorage(AppSettings.Key.notchGlowOnHover)
    private var notchGlowOnHover = AppSettings.Default.notchGlowOnHover

    /// The cursor is resting on the notch.
    @State private var isCursorOnNotch = false

    /// 0...1 — the one-off glow shown the first time ARC opens.
    @State private var introGlowLevel: Double = 0

    /// Which colour of the cycle the glow is on.
    @State private var glowCycleIndex = 0

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

    /// A morph's surface is never allowed to be smaller than the smaller
    /// of its start and end sizes, whatever the spring does in between.
    @State private var backdropFloor: CGSize = .zero

    /// 0 = compact shadow, 1 = expanded shadow. Its OWN state, animated
    /// by its own `withAnimation` — an `.animation(value:)` modifier on
    /// the island would override the animation of everything beneath it
    /// (it once turned Music's spring into a slow ease).
    @State private var shadowExpansion: CGFloat = 0

    /// The colour the island's shadow glows — the accent of whatever is
    /// showing. `nil` is the plain black shadow. Updated on its own
    /// state so it can fade between colours without touching any other
    /// animation.
    @State private var shadowAccent: Color?

    /// The right half's accent while two activities share the pill.
    @State private var shadowAccentRight: Color?

    /// The shared pill is shown from this state, flipped INSIDE a
    /// `withAnimation`, so swapping between the single and shared pill
    /// actually animates (a view swap driven by a derived property has
    /// no animation context and just pops).
    @State private var showsSplitContent = false

    /// Bumped when an activity's size changes on its own (the launcher
    /// changing page), so `visibleSize` is read again.
    @State private var layoutTick = 0

    /// The last shared-pill glow, kept so it can fade out when the pill
    /// opens (or the second activity leaves) instead of being cut.
    @State private var heldSplitGlow: SplitGlow?

    /// Hover-to-open launcher: the cursor is resting on the notch, and a
    /// short dwell is running (so brushing past it doesn't open anything).
    @State private var isPointerOnNotch = false
    @State private var notchHoverWork: DispatchWorkItem?

    /// Both halves of the shared pill, captured while it's up — so when
    /// the second activity ends, its half is still there to fade out
    /// instead of vanishing the instant the manager forgets it.
    @State private var splitSnapshot: SplitSnapshot?

    /// Duration for the very small horizontal enter/exit animation.
    ///
    /// This is intentionally separate from the existing morph animation.
    private let presentationAnimationDuration:
        TimeInterval = AnimationTokens.exitSettleDuration

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

    /// Corner radii for the black surface, derived CONTINUOUSLY from its
    /// height: a 33pt pill has the flat notch-flared top and small bottom
    /// corners; a tall card is fully rounded. Because the radii follow
    /// the (animated) height, they morph with the size — the top edge
    /// never snaps from round to flat.
    private var surfaceRoundness: CGFloat {
        let compact: CGFloat = 33
        let card: CGFloat = 74
        return min(1, max(0, (handoverBackdropSize.height - compact) / (card - compact)))
    }

    private var surfaceTopRadius: CGFloat {
        DesignTokens.Shape.compactTopRadius
            + (DesignTokens.Shape.expandedTopRadius - DesignTokens.Shape.compactTopRadius)
            * surfaceRoundness
    }

    private var surfaceBottomRadius: CGFloat {
        DesignTokens.Shape.compactBottomRadius
            + (DesignTokens.Shape.expandedBottomRadius - DesignTokens.Shape.compactBottomRadius)
            * surfaceRoundness
    }

    /// The size of the pill actually on screen right now.
    private var visibleSize: CGSize {

        // Re-read when the launcher's panel changes height.
        _ = layoutTick

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

    /// Left and right glow colours (and the pill they sit under) while
    /// two activities share the pill; `nil` otherwise.
    private struct SplitGlow: Equatable {
        var left: Color
        var right: Color
        var size: CGSize
    }

    private var splitGlow: SplitGlow? {

        guard isSplitMode, let left = shadowAccent, let right = shadowAccentRight else {
            return nil
        }

        return SplitGlow(left: left, right: right, size: visibleSize)
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        a + (b - a) * t
    }

    private func lerp(_ a: Double, _ b: Double, _ t: CGFloat) -> Double {
        a + (b - a) * Double(t)
    }

    // MARK: - Shadow values
    //
    // Broken out of `body`: inlined, the nested `lerp`s were more than
    // the type-checker would take.

    private var ambientShadowColor: Color {

        let resting = isPrimed
            ? DesignTokens.Shadow.hoverOpacity
            : DesignTokens.Shadow.restOpacity

        let opacity = lerp(resting, DesignTokens.Shadow.expandedOpacity, shadowExpansion)

        return Color.black.opacity(opacity)
    }

    private var ambientShadowRadius: CGFloat {

        let resting = isPrimed
            ? DesignTokens.Shadow.hoverRadius
            : DesignTokens.Shadow.restRadius

        return lerp(resting, DesignTokens.Shadow.expandedRadius, shadowExpansion)
    }

    private var ambientShadowY: CGFloat {

        let resting = isPrimed
            ? DesignTokens.Shadow.hoverYOffset
            : DesignTokens.Shadow.restYOffset

        return lerp(resting, DesignTokens.Shadow.expandedYOffset, shadowExpansion)
    }

    private var accentShadowColor: Color {

        // A shared pill draws its own two-colour glow instead.
        guard splitGlow == nil, let accent = shadowAccent else {
            return Color.clear
        }

        // Faint at rest, strong on hover, and settling — once the card
        // is open — a touch above the resting level.
        let base = isPrimed
            ? DesignTokens.Shadow.accentHoverOpacity
            : DesignTokens.Shadow.accentRestOpacity

        let level = lerp(base, DesignTokens.Shadow.accentExpandedOpacity, shadowExpansion)

        return accent.opacity(level)
    }

    private var accentShadowRadius: CGFloat {

        let base = isPrimed
            ? DesignTokens.Shadow.accentHoverRadius
            : DesignTokens.Shadow.accentRestRadius

        return lerp(base, DesignTokens.Shadow.accentExpandedRadius, shadowExpansion)
    }

    private var accentShadowY: CGFloat {

        let base = isPrimed
            ? DesignTokens.Shadow.hoverYOffset
            : DesignTokens.Shadow.restYOffset

        return lerp(base, DesignTokens.Shadow.expandedYOffset, shadowExpansion)
    }

    // MARK: - Shadows

    /// Rounding for a surface of this height — the same curve
    /// `surfaceRoundness` follows, so the shadow's corners match.
    private func casterRadii(forHeight height: CGFloat) -> (top: CGFloat, bottom: CGFloat) {

        let t = min(1, max(0, (height - 33) / (74 - 33)))

        let top = DesignTokens.Shape.compactTopRadius
            + (DesignTokens.Shape.expandedTopRadius - DesignTokens.Shape.compactTopRadius) * t

        let bottom = DesignTokens.Shape.compactBottomRadius
            + (DesignTokens.Shape.expandedBottomRadius - DesignTokens.Shape.compactBottomRadius) * t

        return (top, bottom)
    }

    /// The size the shadows are cast from. It springs to `visibleSize`
    /// but deliberately a touch LATE when growing and EARLY when
    /// shrinking, so the stand-in is never bigger than the real surface
    /// — the shadow never shows up around an island that hasn't opened yet.
    @State private var casterSize: CGSize = .zero

    private func moveCaster(from old: CGSize, to new: CGSize) {

        let growing = new.width * new.height >= old.width * old.height

        let spring: Animation = growing
            ? .spring(response: 0.38, dampingFraction: 1)
            : .spring(response: 0.16, dampingFraction: 1)

        withAnimation(spring) {
            casterSize = new
        }
    }

    /// Casts every shadow the island has — ambient, accent glow, contact —
    /// from a stand-in for the island's surface, sitting under it.
    private var shadowCaster: some View {

        let size = casterSize
        let radii = casterRadii(forHeight: size.height)

        return IslandShape(topRadius: radii.top, bottomRadius: radii.bottom)
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .shadow(
                color: ambientShadowColor,
                radius: ambientShadowRadius,
                x: 0,
                y: ambientShadowY
            )
            .shadow(
                color: accentShadowColor,
                radius: accentShadowRadius,
                x: 0,
                y: accentShadowY
            )
            .shadow(
                color: DesignTokens.Shadow.contactColor,
                radius: DesignTokens.Shadow.contactRadius,
                x: 0,
                y: DesignTokens.Shadow.contactYOffset
            )
            .animation(AnimationTokens.hoverPrimeTransition, value: isPrimed)
            .scaleEffect(
                x: isPresentationVisible ? 1 : notchScale.width,
                y: isPresentationVisible ? 1 : notchScale.height,
                anchor: .top
            )
            .animation(
                isPresentationVisible ? AnimationTokens.enterSpring : AnimationTokens.exitSpring,
                value: isPresentationVisible
            )
            .offset(y: isDocked ? 0 : dockDragOffset)
            .opacity(renderedActivity == nil || isDocked ? 0 : 1)
            .allowsHitTesting(false)
    }

    // MARK: - Notch ears

    /// The two small concave fillets where a flat-topped pill meets the
    /// top of the screen, drawn at the root so EVERY activity — Music
    /// included — gets exactly the same curve. Only for compact pills; a
    /// tall card has rounded top corners instead.
    private var notchEars: some View {

        let flare = DesignTokens.Shape.notchFlare

        // Follows the pill's own (animated) size, so the flares slide in
        // with its edges instead of appearing once it has settled. They
        // fade out as it grows into a card, and back in as it shrinks.
        let size = earSize == .zero ? visibleSize : earSize

        let compactness = 1 - min(1, max(0, (size.height - 36) / 12))

        let visible = !isDocked && renderedActivity != nil && !showHandoverBackdrop

        return ZStack(alignment: .top) {

            NotchEarShape(isLeft: true)
                .fill(DesignTokens.Color.islandBackground)
                .frame(width: flare, height: flare)
                .offset(x: -(size.width / 2 + flare / 2))

            NotchEarShape(isLeft: false)
                .fill(DesignTokens.Color.islandBackground)
                .frame(width: flare, height: flare)
                .offset(x: size.width / 2 + flare / 2)
        }
        .frame(
            width: max(DesignTokens.sharedCanvasSize.width, size.width + flare * 2),
            height: flare,
            alignment: .top
        )
        .opacity(visible ? compactness : 0)
        .animation(.easeOut(duration: 0.25), value: showHandoverBackdrop)
        .allowsHitTesting(false)
    }

    /// The pill's size as the ears follow it — the same springs the
    /// surface uses, including collapsing's short wait.
    @State private var earSize: CGSize = .zero

    private func moveEars(from old: CGSize, to new: CGSize) {

        let growing = new.width * new.height >= old.width * old.height

        let spring: Animation = growing
            ? AnimationTokens.expandSpring
            : AnimationTokens.collapseSpring.delay(AnimationTokens.collapseShapeDelay)

        withAnimation(spring) {
            earSize = new
        }
    }

    // MARK: - Notch glow

    /// The glow's source shape: exactly this wide and this tall. The glow
    /// itself spreads outward from it.
    private static let notchGlowSize = CGSize(
        width: DesignTokens.FileDropMetrics.notchWidth,
        height: DesignTokens.Shape.collapsedNotchHeight
    )

    /// The colour the glow is right now. Changing it (a new choice in
    /// Settings, or the next step of the cycle) cross-fades.
    private var notchGlowTint: Color {

        let choice = NotchGlowColor(rawValue: notchGlowColor) ?? .white

        if choice == .cycle {
            let palette = NotchGlowColor.cyclePalette
            return palette[glowCycleIndex % palette.count].color
        }

        return choice.color
    }

    /// Whether the glow is lit by the user's setting (as opposed to the
    /// one-off first-launch glow).
    private var glowIsOn: Bool {
        notchGlowEnabled && renderedActivity == nil
    }

    /// A soft halo around the notch itself, drawn behind a notch-sized
    /// black shape so it reads as light spilling out from behind it (the
    /// real notch hides the part behind the screen's edge).
    private var notchGlow: some View {

        let size = Self.notchGlowSize

        let tint = notchGlowTint
        let intensity = max(notchGlowIntensity, 0)

        let shape = IslandShape(
            topRadius: DesignTokens.Shape.compactTopRadius,
            bottomRadius: DesignTokens.Shape.compactBottomRadius
        )

        let hoverLit = notchGlowOnHover && isCursorOnNotch && renderedActivity == nil

        let level = max(glowIsOn || hoverLit ? 1 : 0, introGlowLevel)

        return ZStack(alignment: .top) {

            // Wide, faint bloom.
            shape
                .fill(tint)
                .frame(width: size.width, height: size.height)
                .blur(radius: 7 * (0.6 + 0.4 * intensity))
                .opacity(min(0.55 * intensity, 1))

            // Tighter, brighter edge.
            shape
                .fill(tint)
                .frame(width: size.width, height: size.height)
                .blur(radius: 3 * (0.6 + 0.4 * intensity))
                .opacity(min(0.8 * intensity, 1))

            // The notch itself, over the top.
            shape
                .fill(DesignTokens.Color.islandBackground)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .opacity(level)
        .animation(.easeInOut(duration: 0.6), value: tint)
        .animation(.easeInOut(duration: 0.4), value: glowIsOn)
        .animation(.easeInOut(duration: 0.3), value: hoverLit)
        .allowsHitTesting(false)
        // Steps the cycle colour on, slowly, only while it can be seen.
        .task(id: notchGlowColor == NotchGlowColor.cycle.rawValue && (level > 0)) {

            guard notchGlowColor == NotchGlowColor.cycle.rawValue, level > 0 else {
                return
            }

            while !Task.isCancelled {

                try? await Task.sleep(nanoseconds: 3_500_000_000)

                if Task.isCancelled { break }

                glowCycleIndex += 1
            }
        }
    }

    /// The first-launch glow: fades in, holds a moment, fades out.
    private func playIntroGlow() {

        withAnimation(.easeInOut(duration: 1.0)) {
            introGlowLevel = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
            withAnimation(.easeInOut(duration: 1.6)) {
                introGlowLevel = 0
            }
        }
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

    /// The island itself: content, scale-in, side bubbles.
    private var islandVisual: some View {

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
                            topRadius: surfaceTopRadius,
                            bottomRadius: surfaceBottomRadius
                        )
                        .fill(DesignTokens.Color.islandBackground)
                        .frame(
                            width: max(handoverBackdropSize.width, backdropFloor.width),
                            height: max(handoverBackdropSize.height, backdropFloor.height)
                        )
                        .allowsHitTesting(false)
                    }

                    if showsSplitContent, let split = splitSnapshot {

                        // Laid out at its final width but revealed
                        // through the live surface, so nothing pokes out
                        // of the black while the pill is still growing.
                        SplitIslandContent(
                            leading: split.leading,
                            trailing: split.trailing,
                            earWidth: split.earWidth
                        )
                        .id("split")
                        .mask(alignment: .top) {
                            surfaceMask
                        }
                        .transition(
                            .opacity.animation(
                                .easeOut(duration: 0.18)
                                    .delay(AnimationTokens.contentRevealDelay + 0.04)
                            )
                        )

                    } else {

                        let shown = presentedActivity ?? activity

                        shown.islandView(
                            isExpanded:
                                isExpanded
                        )
                        .id(shown.id)
                        .mask(alignment: .top) {
                            surfaceMask
                        }
                        // On a hand-over the surface leads and the content
                        // follows once there's room — it used to fade in
                        // while the island was still opening.
                        .transition(
                            .asymmetric(
                                insertion: .opacity
                                    .animation(.easeOut(duration: 0.22).delay(0.12))
                                    .combined(with: .scale(scale: 0.96, anchor: .top)),
                                removal: .opacity
                                    .animation(.easeIn(duration: 0.12))
                            )
                        )
                    }
                }
                // At least canvas-wide: a pill exactly as wide as itself
                // (Music's) would clip the notch flare and shadow that
                // spill just outside its edges.
                .frame(
                    minWidth: DesignTokens.sharedCanvasSize.width,
                    alignment: .top
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

                // As wide as the island is whenever it has content, so
                // `isOnNotch` (which measures from the middle of that
                // width) lands on the real notch even with nothing showing.
                Color.clear
                    .frame(
                        width:
                            max(DesignTokens.sharedCanvasSize.width, compactSize.width),

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

        // Grows out of the notch with a little spring; shrinks back into
        // it without bouncing.
        .animation(
            isPresentationVisible
                ? AnimationTokens.enterSpring
                : AnimationTokens.exitSpring,

            value:
                isPresentationVisible
        )

        // Detached bubbles beside the island. Deliberately OUTSIDE the
        // notch scale above, so they don't squash with the pill.
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                notchEars
                sideBubbles
            }
        }

        // ---------------------------------------------------------
        // IMPORTANT:
        //
        // Watch ownership separately so we can keep the old island
        // mounted while it shrinks to the centre.
        // ---------------------------------------------------------
    }

    /// Lifecycle, shadow, glow — everything that styles the island.
    private var islandStyled: some View {

        islandVisual

        .onAppear {

            syncInitialPresentation()

            casterSize = visibleSize
            earSize = visibleSize

            if isSplitMode {
                captureSplit()
                showsSplitContent = true
                heldSplitGlow = splitGlow
            }
        }

        .task {

            while !Task.isCancelled {

                let accent = (isSplitMode
                    ? activityManager.ownedActivity
                    : presentedActivity)?.shadowAccent

                let rightAccent = isSplitMode
                    ? activityManager.secondaryActivity?.shadowAccent
                    : nil

                if accent != shadowAccent || rightAccent != shadowAccentRight {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        shadowAccent = accent
                        shadowAccentRight = rightAccent
                    }
                }

                try? await Task.sleep(nanoseconds: 300_000_000)
            }
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

        // Floating-surface shadows, like Apple's: a large soft ambient
        // shadow that grows as the island opens, a tight contact shadow
        // that keeps its edge crisp (both neutral black), and — while the
        // compact pill sits there — a glow in the activity's colour that
        // swells on hover and is gone once the card is open.
        // The island's shadows come from `shadowCaster`, a shape of their
        // own — not from whatever pixels happen to be on screen. Drawn from
        // the content they thinned out and swelled with every cross-fade
        // and surface swap (a shared pill opening was the worst of it).
        .background(alignment: .top) {
            shadowCaster
        }

        // Shared pill: the glow is split down the middle — each half
        // takes its own activity's colour.
        .background(alignment: .top) {

            if let glow = splitGlow ?? heldSplitGlow {

                let isLive = splitGlow != nil

                IslandShape(
                    topRadius: DesignTokens.Shape.compactTopRadius,
                    bottomRadius: DesignTokens.Shape.compactBottomRadius
                )
                .fill(
                    LinearGradient(
                        stops: [
                            .init(color: glow.left, location: 0),
                            .init(color: glow.left, location: 0.46),
                            .init(color: glow.right, location: 0.54),
                            .init(color: glow.right, location: 1)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: glow.size.width, height: glow.size.height)
                .blur(radius: isPrimed ? 14 : 11)
                .offset(y: isPrimed ? 7 : 5)
                .opacity(
                    !isLive
                        ? 0
                        : isPrimed
                            ? DesignTokens.Shadow.accentHoverOpacity
                            : DesignTokens.Shadow.accentRestOpacity
                )
                .animation(AnimationTokens.hoverPrimeTransition, value: isPrimed)
                // Fades out / in over its own curve — the pill's spring
                // would otherwise snap it, and the layer must outlive
                // the split so there's something left to fade.
                .animation(.easeInOut(duration: 0.35), value: isLive)
                .allowsHitTesting(false)
            }
        }

        // Optional glow around the bare notch — only while nothing else
        // is on the island (activities bring their own glow).
        .background(alignment: .top) {
            notchGlow
        }

        // ---------------------------------------------------------
        // EXISTING HOVER
        // ---------------------------------------------------------
    }

    var body: some View {

        islandStyled

        // Only used to know WHICH half of a shared pill the cursor is on
        // — whether to expand at all is `WindowManager`'s call below.
        .onContinuousHover { phase in

            switch phase {

            case .active(let point):

                hoverSide = point.x < max(
                    DesignTokens.sharedCanvasSize.width,
                    visibleSize.width
                ) / 2
                    ? .leading
                    : .trailing

                isCursorOnNotch = isOnNotch(point)

                updateNotchHover(at: point)

            case .ended:

                isCursorOnNotch = false

                cancelNotchHover()
            }
        }

        .onChange(of: visibleSize) { old, new in

            previousVisibleSize = old

            moveCaster(from: casterSize == .zero ? old : casterSize, to: new)

            moveEars(from: earSize == .zero ? old : earSize, to: new)

            if isSplitMode { captureSplit() }

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
        .onChange(of: isSplitMode) { _, now in

            if now { captureSplit() }

            // The content swap goes in an animation of its own, picked by
            // direction like the surface's (springy growing, no overshoot
            // shrinking).
            withAnimation(
                AnimationTokens.handover(from: previousVisibleSize, to: visibleSize)
            ) {
                showsSplitContent = now
            }

            morphSurface()
        }

        .onChange(of: splitGlow) { _, glow in
            if let glow { heldSplitGlow = glow }
        }

        // The two halves can change while the pill is up (the second
        // activity swapped for another) — keep the snapshot current.
        .onChange(of: activityManager.secondaryActivity?.id) { _, _ in
            if isSplitMode { captureSplit() }
        }

        .onChange(of: activityManager.ownedActivity?.id) { _, _ in
            if isSplitMode { captureSplit() }
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

            withAnimation(.easeInOut(duration: 0.25)) {
                shadowExpansion = expanded ? 1 : 0
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
                for: .islandIntroGlow
            )
        ) { _ in
            playIntroGlow()
        }

        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandLauncherLayoutChanged
            )
        ) { _ in
            layoutTick += 1
        }

        // The launcher handing straight over to the card it's showing
        // (its Now Playing title was clicked): once the launcher has
        // closed and that activity owns the island, open it.
        .onReceive(
            NotificationCenter.default.publisher(
                for: .islandExpandNow
            )
        ) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                guard
                    renderedActivity != nil,
                    renderedActivity?.kind != .launcher,
                    !isExpanded
                else {
                    return
                }
                expandImmediately()
            }
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

        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    handleTap(at: value.location)
                }
        )

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

            // A short grace period first: when one activity hands the
            // island straight to another (the launcher closing as a
            // timer starts), the owner is briefly nil in between.
            // Shrinking into the notch for that gap, then growing back
            // out, is the glitch — so only start the exit if nobody
            // takes over. A new owner cancels this and morphs instead.
            let exit =
                DispatchWorkItem { [self] in

                    guard activityManager.ownedActivity == nil else {
                        return
                    }

                    isPresentationVisible =
                        false

                    let workItem =
                        DispatchWorkItem { [self] in

                            // Only remove the rendered activity if there
                            // still isn't a new owner waiting.
                            guard
                                activityManager
                                    .ownedActivity
                                == nil
                            else {
                                return
                            }

                            renderedActivity =
                                nil

                            // Nothing left to be expanded — otherwise the
                            // hover region stays expanded-sized around an
                            // empty notch.
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
                }

            presentationWorkItem =
                exit

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.12,
                execute: exit
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

            let oldSize = visibleSize

            let newSize = isExpanded
                ? newActivity.expandedSize
                : newActivity.compactSize

            // Plant the surface at the OLD size first, with no animation
            // and a frame of its own. Setting it and springing it to the
            // new size in one go makes SwiftUI animate from the last
            // RENDERED size instead — the surface would start at the
            // smaller of the two and the old card would just vanish.
            var instant = Transaction()
            instant.disablesAnimations = true

            withTransaction(instant) {
                handoverBackdropSize = oldSize
                backdropFloor = CGSize(
                    width: min(oldSize.width, newSize.width),
                    height: min(oldSize.height, newSize.height)
                )
                showHandoverBackdrop = true
            }

            DispatchQueue.main.async {

                withAnimation(AnimationTokens.handover(from: oldSize, to: newSize)) {

                    renderedActivity = newActivity

                    handoverBackdropSize = newSize
                }
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

    // MARK: - Surface mask

    /// What the island's content is revealed through. While the surface
    /// is morphing it is the live surface itself, so nothing — content,
    /// or an activity's own pill and its flare — can draw outside it.
    /// Otherwise it's a rectangle far bigger than any island, which
    /// clips nothing (the notch flare spills outside a view's own
    /// bounds, so a tight mask would cut it off).
    private var surfaceMask: some View {

        ZStack(alignment: .top) {

            if showHandoverBackdrop {

                IslandShape(
                    topRadius: surfaceTopRadius,
                    bottomRadius: surfaceBottomRadius
                )
                .fill(Color.black)
                .frame(
                    width: max(handoverBackdropSize.width, backdropFloor.width),
                    height: max(handoverBackdropSize.height, backdropFloor.height)
                )

            } else {

                Rectangle()
                    .fill(Color.black)
                    .frame(width: 1400, height: 700)
            }
        }
        .frame(width: 1400, height: 700, alignment: .top)
    }

    // MARK: - Shared pill snapshot

    private func captureSplit() {

        guard
            let earWidth = activityManager.splitEarWidth,
            let leading = activityManager.ownedActivity?.earView(side: .leading),
            let trailing = activityManager.secondaryActivity?.earView(side: .trailing)
        else {
            return
        }

        splitSnapshot = SplitSnapshot(
            leading: leading,
            trailing: trailing,
            earWidth: earWidth
        )
    }

    // MARK: - Surface morph

    /// Starts the black surface at the size the island WAS and springs it
    /// to the size it IS now, so layout changes read as one shape
    /// reshaping instead of one view swapping for another.
    private func morphSurface() {

        handoverWorkItem?.cancel()

        let from = previousVisibleSize
        let to = visibleSize

        var instant = Transaction()
        instant.disablesAnimations = true

        withTransaction(instant) {
            handoverBackdropSize = from
            backdropFloor = CGSize(
                width: min(from.width, to.width),
                height: min(from.height, to.height)
            )
            showHandoverBackdrop = true
        }

        DispatchQueue.main.async {
            withAnimation(AnimationTokens.handover(from: from, to: to)) {
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

    // MARK: - Hover the notch → launcher

    /// Whether `point` (in the island's own coordinates) is on the notch.
    private func isOnNotch(_ point: CGPoint) -> Bool {

        let frameWidth = max(
            DesignTokens.sharedCanvasSize.width,
            visibleSize.width
        )

        // The measured notch, plus a generous margin: the cursor slips
        // behind the notch, so a target exactly its size is hard to hit.
        return abs(point.x - frameWidth / 2) <= NotchGeometry.targetHalfWidth
            && point.y <= NotchGeometry.targetHeight
    }

    /// How far down from the top of the screen counts as "the very top
    /// edge" for the top-edge-only launcher trigger.
    private static let topEdgeHeight: CGFloat = 6

    /// The centered strip along the top of the screen.
    private func isOnTopEdge(_ point: CGPoint) -> Bool {
        isOnNotch(point) && point.y <= Self.topEdgeHeight
    }

    /// Whether `point` is somewhere the launcher may be opened from, per
    /// the "Open the launcher by" setting.
    private func isOnLauncherTrigger(_ point: CGPoint) -> Bool {

        switch AppSettings.launcherTrigger {
        case .notch: return isOnNotch(point)
        case .topEdge: return isOnTopEdge(point)
        case .off: return false
        }
    }

    /// With "open the launcher on hover" on, resting the cursor on the
    /// notch for a moment opens it. Off, this does nothing.
    private func updateNotchHover(at point: CGPoint) {

        guard
            AppSettings.launcherOpensOnHover,
            !isDocked,
            isOnLauncherTrigger(point)
        else {
            cancelNotchHover()
            return
        }

        guard !isPointerOnNotch else { return }

        isPointerOnNotch = true

        // Already the launcher: nothing to open.
        guard activityManager.ownedActivity?.kind != .launcher else { return }

        let work = DispatchWorkItem {

            // The launcher takes the island: drop any pending "expand".
            hoverWorkItem?.cancel()
            hoverWorkItem = nil

            NotificationCenter.default.post(
                name: .islandOpenLauncher,
                object: nil
            )
        }

        notchHoverWork = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + 0.25,
            execute: work
        )
    }

    private func cancelNotchHover() {

        isPointerOnNotch = false

        notchHoverWork?.cancel()
        notchHoverWork = nil
    }

    // MARK: - Tap

    /// A click on the notch itself — the middle of the island, where the
    /// hardware notch sits — opens (or closes) the launcher, whatever is
    /// on the island. A click anywhere else on the pill expands it, as
    /// before.
    private func handleTap(at point: CGPoint) {

        // A tap on the docked island brings it back immediately.
        if isDocked {

            undock()

            return
        }

        // Whether this click opens the launcher, per the "Open the
        // launcher by" setting. By default that's the notch (measured
        // notch plus margin), or any click on an empty island.
        let opensLauncher: Bool

        switch AppSettings.launcherTrigger {
        case .notch: opensLauncher = renderedActivity == nil || isOnNotch(point)
        case .topEdge: opensLauncher = isOnTopEdge(point)
        case .off: opensLauncher = false
        }

        if opensLauncher {

            NotificationCenter.default.post(
                name: .islandToggleLauncher,
                object: nil
            )

            return
        }

        // Nothing on the island and not a launcher click: nothing to do.
        if renderedActivity == nil { return }

        // A tap on the compact island bypasses the hover delay.
        if !isExpanded {

            expandImmediately()
        }
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


/// Both halves of a shared pill, kept so they can fade out after the
/// activity manager has already moved on.
private struct SplitSnapshot {
    let leading: AnyView
    let trailing: AnyView
    let earWidth: CGFloat
}
