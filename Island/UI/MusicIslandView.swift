import SwiftUI

/// Music's single island presentation — compact and expanded are NOT two
/// separate views being swapped anymore, just one view's parameters
/// changing under `isExpanded`.
///
/// WHY THIS REPLACED `MusicCompactView` + `MusicExpandedView`:
///
/// The old architecture had `IslandRootView` doing
/// `if isExpanded { activity.expandedView() } else { activity.compactView() }`,
/// where those two methods were type-erased into two INDEPENDENT `AnyView`s
/// (see `AnyActivity`). SwiftUI has no way to know those two `AnyView`s are
/// "the same island, different state" — structurally, it's an unrelated
/// view being removed and a new, different one being inserted.
/// `matchedGeometryEffect` smoothed over exactly 3 explicitly-tagged
/// elements (the shape, artwork, waveform), but everything else — the
/// CONTAINER's own declared width, and every element not explicitly
/// tagged — had no smooth transition at all: the instant the branch
/// flipped, SwiftUI immediately laid out the full 390pt-wide expanded
/// content. Meanwhile the actual AppKit window — animating independently
/// via `SpringAnimator`, with no idea SwiftUI had already snapped to the
/// final layout — was still mid-grow from 263pt. Content that fit within
/// the window's currently-smaller width appeared instantly; everything
/// further right (the waveform, transport buttons, AirPlay) was clipped
/// until the window physically caught up. Visually: the island appeared
/// to grow from the left instead of as one shape.
///
/// The fix is architectural, not a tuning tweak: use ONE view whose
/// `.frame(width:height:)`, `.position(...)`, and `.opacity(...)` are
/// plain ternaries on `isExpanded`. SwiftUI's built-in animation of a
/// SINGLE PERSISTING view's modifiers is reliably frame-synchronized —
/// there is no second, independent mechanism (an AnyView swap plus an MGE
/// proxy) left to fall out of sync with the AppKit window's spring in the
/// first place. `matchedGeometryEffect` is no longer used here at all.
///
/// SECOND ROOT CAUSE (found later, same symptom family): even after the
/// above fix, small-travel elements (album art, ~35pt of motion) still
/// visibly desynced from large-travel ones (the waveform, ~110pt) during
/// the animation. That was `WindowManager` independently animating the
/// actual AppKit window frame with its own hand-rolled physics loop,
/// timed to match this view's spring but never literally the same
/// simulation — any tiny drift between the two was proportionally much
/// louder on a small move than a large one. `WindowManager` no longer
/// resizes the window at all; this view's own `.frame()`/`.clipped()`
/// below is now the ONLY thing driving the visible size.
struct MusicIslandView: View {
    @ObservedObject var activity: MusicActivity
    
    var isExpanded: Bool

    /// The album art's dominant color, extracted once per artwork change
    /// (see `ArtworkColorExtractor`) and shared by both the glow AND the
    /// waveform below — one computed value, two consumers, rather than
    /// each independently computing (and potentially drifting from) their
    /// own version of "the artwork's color."
    @State private var artworkColor: Color = DesignTokens.Color.musicAccent

    private typealias Metrics = DesignTokens.MusicMetrics
    private typealias ShapeTokens = DesignTokens.Shape

    private var compactSize: CGSize {
        CGSize(width: Metrics.compactWidth, height: Metrics.compactHeight)
    }
    private var expandedSize: CGSize {
        CGSize(width: Metrics.expandedWidth, height: Metrics.expandedHeight)
    }
    private var currentSize: CGSize { isExpanded ? expandedSize : compactSize }

    // MARK: - Shared elements — present in both states, just
    // repositioned/resized. No matchedGeometryEffect needed: since this is
    // one persistent view, a plain ternary on `.position()`/`.frame()`
    // already animates smoothly under the enclosing `withAnimation`.

    private var artSize: CGFloat { isExpanded ? 65 : Metrics.compactIconSize }
    private var artCornerRadius: CGFloat {
        isExpanded ? Metrics.albumArtCornerRadius : Metrics.compactIconCornerRadius
    }
    private var artCenter: CGPoint {
        isExpanded
            ? CGPoint(x: 24 + 65 / 2, y: 24 + 65 / 2)
            : CGPoint(x: Metrics.compactEdgePadding + Metrics.compactIconSize / 2, y: DesignTokens.MusicMetrics.compactContentCenterY)
    }

    private var waveformSize: CGSize {
        isExpanded
            ? CGSize(width: 25.57, height: 24)
            : CGSize(width: Metrics.compactIconSize, height: Metrics.compactIconSize)
    }
    private var waveformCenter: CGPoint {
        isExpanded
            ? CGPoint(x: 338.85 + 25.57 / 2, y: 24 + 24 / 2)
            : CGPoint(
                x: compactSize.width - Metrics.compactEdgePadding - Metrics.compactIconSize / 2,
                y: DesignTokens.MusicMetrics.compactContentCenterY
            )
    }

    // MARK: - Expanded-only elements — always present in the tree, gated
    // by opacity rather than structurally inserted/removed. Their own
    // coordinates never change (they're only ever visible in the expanded
    // layout), so no ternary needed on the coordinates themselves — only
    // on whether they're shown.

    private let titleOrigin = CGPoint(x: 106, y: 36)
    private var titleWidth: CGFloat { 338.85 - titleOrigin.x - 16 }

    private let progressOrigin = CGPoint(x: 71, y: 112)
    private let progressSize = CGSize(width: 242, height: 7)

    private let elapsedOrigin = CGPoint(x: 24, y: 106)
    private let remainingOrigin = CGPoint(x: 333, y: 106)

    private let rowCenterY: CGFloat = 159.9
    private var pauseCenter: CGPoint { CGPoint(x: expandedSize.width / 2, y: rowCenterY) }
    private var previousCenter: CGPoint {
        CGPoint(x: pauseCenter.x - Metrics.playbackButtonSpacing, y: rowCenterY)
    }
    private var nextCenter: CGPoint {
        CGPoint(x: pauseCenter.x + Metrics.playbackButtonSpacing, y: rowCenterY)
    }
    private let airplayCenter = CGPoint(x: 335.5, y: 159.9)

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandShape(
                topRadius: isExpanded ? ShapeTokens.expandedTopRadius : ShapeTokens.compactTopRadius,
                bottomRadius: isExpanded ? ShapeTokens.expandedBottomRadius : ShapeTokens.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)

            AlbumArtView(
                image: activity.playbackState?.artwork,
                size: artSize,
                cornerRadius: artCornerRadius,
                showGlow: isExpanded,
                glowColor: artworkColor
            )
            .position(artCenter)

            Waveform(isPlaying: activity.playbackState?.isPlaying ?? false, color: artworkColor)
                .frame(width: waveformSize.width, height: waveformSize.height)
                .position(waveformCenter)

            titleBlock
            progressBar
            elapsedLabel
            remainingLabel
            previousButton
            pauseButton
            nextButton
            airplayButton
        }
        .frame(width: currentSize.width, height: currentSize.height)
        // Clips to the CURRENT animated frame every frame, in lockstep
        // with the same `.frame` modifier above — not a separate clip
        // mask that could itself fall out of sync. This is MORE important
        // now that the window itself is static (see `WindowManager`) and
        // no longer does this clipping for free at the AppKit level —
        // without this, expanded-only content would visibly bleed outside
        // the compact pill's bounds during the compact state and
        // mid-transition instead of being contained by it.
        .task(id: activity.playbackState?.artwork?.tiffRepresentation) {
            let artwork =
                activity.playbackState?.artwork
                ?? NSImage(named: "Currents")

            artworkColor = ArtworkColorExtractor.dominantColor(
                from: artwork,
                fallback: DesignTokens.Color.musicAccent
            )
        }
    }

    // MARK: - Expanded-only content
    //
    // Each of these gets an EXPLICIT slide-up-and-fade: starts offset below
    // its final position with zero opacity, animates up to its resting
    // spot. This is deliberate, not decorative — previously these had NO
    // motion of their own; they sat at their final absolute position the
    // entire time, with only opacity animating, and the ONLY reason they
    // appeared to "enter" at all was that `.clipped()`'s growing bounds
    // happened to reveal them as the frame grew. Since the frame grows
    // from top-leading, elements positioned toward the bottom-right of the
    // canvas (buttons, AirPlay, progress bar) were the last to be
    // uncovered — which is exactly the "pops in from the bottom-right"
    // artifact. Giving each element its own real offset animation means it
    // now enters on its own terms regardless of when the clip mask catches
    // up to it.
    private let entranceOffsetY: CGFloat = 14

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(activity.playbackState?.title ?? "")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(activity.playbackState?.artist ?? "")
                .font(DesignTokens.Typography.subtitle)
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: titleWidth, alignment: .leading)
        .offset(x: titleOrigin.x, y: titleOrigin.y + (isExpanded ? 0 : entranceOffsetY))
        .opacity(isExpanded ? 1 : 0)
        .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.02 : 0), value: isExpanded)
        .allowsHitTesting(isExpanded)
    }

    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule()
                .fill(DesignTokens.Color.primaryText)
                .frame(width: progressSize.width * progressFraction)
        }
        .frame(width: progressSize.width, height: progressSize.height)
        .offset(x: progressOrigin.x, y: progressOrigin.y + (isExpanded ? 0 : entranceOffsetY))
        .opacity(isExpanded ? 1 : 0)
        .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.05 : 0), value: isExpanded)
        .allowsHitTesting(isExpanded)
    }

    private var elapsedLabel: some View {
        Text(formatted(activity.playbackState?.elapsed ?? 0))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .tracking(DesignTokens.Typography.letterSpacingTight)
            .foregroundStyle(DesignTokens.Color.secondaryText)
            .offset(x: elapsedOrigin.x, y: elapsedOrigin.y + (isExpanded ? 0 : entranceOffsetY))
            .opacity(isExpanded ? 1 : 0)
            .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.05 : 0), value: isExpanded)
    }

    private var remainingLabel: some View {
        Text("-" + formatted(remaining))
            .font(DesignTokens.Typography.timestamp.monospacedDigit())
            .tracking(DesignTokens.Typography.letterSpacingTight)
            .foregroundStyle(DesignTokens.Color.secondaryText)
            .offset(x: remainingOrigin.x, y: remainingOrigin.y + (isExpanded ? 0 : entranceOffsetY))
            .opacity(isExpanded ? 1 : 0)
            .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.05 : 0), value: isExpanded)
    }

    private var previousButton: some View {
        PlaybackButton(systemName: "backward.fill", action: activity.skipBackward, size: 20)
            .opacity(0.7)
            .position(x: previousCenter.x, y: previousCenter.y + (isExpanded ? 0 : entranceOffsetY))
            .opacity(isExpanded ? 1 : 0)
            .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.08 : 0), value: isExpanded)
            .allowsHitTesting(isExpanded)
    }

    private var pauseButton: some View {
        PlaybackButton(
            systemName: (activity.playbackState?.isPlaying ?? false) ? "pause.fill" : "play.fill",
            action: activity.togglePlayPause,
            size: 32
        )
        .frame(width: 34, height: 34)

        .position(x: pauseCenter.x, y: pauseCenter.y + (isExpanded ? 0 : entranceOffsetY))
        .opacity(isExpanded ? 1 : 0)
        .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.08 : 0), value: isExpanded)
        .allowsHitTesting(isExpanded)
    }

    private var nextButton: some View {
        PlaybackButton(systemName: "forward.fill", action: activity.skipForward, size: 20)
            .opacity(0.7)
            .position(x: nextCenter.x, y: nextCenter.y + (isExpanded ? 0 : entranceOffsetY))
            .opacity(isExpanded ? 1 : 0)
            .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.08 : 0), value: isExpanded)
            .allowsHitTesting(isExpanded)
    }

    private var airplayButton: some View {
        Image(systemName: "airplayaudio")
            .font(.system(size: 18))
            .foregroundStyle(DesignTokens.Color.primaryText)
            .frame(width: Metrics.airplayIconSize, height: Metrics.airplayIconSize)
            .position(x: airplayCenter.x, y: airplayCenter.y + (isExpanded ? 0 : entranceOffsetY))
            .opacity(isExpanded ? 1 : 0)
            .animation(AnimationTokens.shapeSpring.delay(isExpanded ? 0.08 : 0), value: isExpanded)
            .allowsHitTesting(isExpanded)
    }

    // MARK: - Derived values (formatting only, not layout)

    private var remaining: TimeInterval {
        max((activity.playbackState?.duration ?? 0) - (activity.playbackState?.elapsed ?? 0), 0)
    }

    private var progressFraction: CGFloat {
        guard let state = activity.playbackState, state.duration > 0 else { return 0 }
        return min(max(state.elapsed / state.duration, 0), 1)
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
