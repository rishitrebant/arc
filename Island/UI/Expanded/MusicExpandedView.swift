import SwiftUI

/// The expanded, hover-triggered presentation of Music.
///
/// A fixed 390×200 canvas, not a responsive layout. Every element is
/// placed at an explicit coordinate inside a single `ZStack(alignment:
/// .topLeading)` — no `HStack`/`VStack`/`Spacer()` composing the overall
/// layout, and no `GeometryReader` measuring anything to derive a
/// position. The ONLY layout container used for composition is the small
/// leading-aligned `VStack` for the title+artist block, since that's the
/// one genuinely dynamic piece of content (title truncates rather than
/// reflowing anything else).
///
/// Coordinates below are the measurements as given — treated as source of
/// truth verbatim, not re-derived or "corrected" against any prior layout.
struct MusicExpandedView: View {
    @ObservedObject var activity: MusicActivity

    @Environment(\.islandNamespace) private var namespace

    /// The fixed coordinate grid. `Origin` values are top-left points, used
    /// with `.offset(x:y:)` against the ZStack's `.topLeading` alignment.
    /// `Center` values are used with `.position(_:)`, which places a view's
    /// center at an absolute point regardless of the parent's alignment.
    private enum Layout {
        static let canvasWidth: CGFloat = DesignTokens.MusicMetrics.expandedWidth   // 390
        static let canvasHeight: CGFloat = DesignTokens.MusicMetrics.expandedHeight // 200

        static let artOrigin = CGPoint(x: 24, y: 24)
        static let artSize: CGFloat = 65

        static let waveformOrigin = CGPoint(x: 338.85, y: 24)
        static let waveformSize = CGSize(width: 25.57, height: 24)

        static let titleOrigin = CGPoint(x: 106, y: 36)
        // No explicit width was given for the title block. Derived from the
        // waveform's fixed x minus a small gap, so a long title truncates
        // before ever reaching the waveform rather than overlapping it.
        static let titleWidth: CGFloat = waveformOrigin.x - titleOrigin.x - 16

        static let progressTrackOrigin = CGPoint(x: 71, y: 112)
        static let progressTrackSize = CGSize(width: 242, height: 7)

        static let elapsedOrigin = CGPoint(x: 24, y: 106)
        static let remainingOrigin = CGPoint(x: 313, y: 106)

        static let previousCenter = CGPoint(x: 101, y: 140)
        static let pauseCenter = CGPoint(x: 178, y: 140)
        static let nextCenter = CGPoint(x: 249, y: 140)
        static let airplayCenter = CGPoint(x: 322, y: 140)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            IslandShape.body(
                topRadius: DesignTokens.Shape.expandedTopRadius,
                bottomRadius: DesignTokens.Shape.expandedBottomRadius
            )
                .fill(DesignTokens.Color.islandBackground)
                .islandMatchedGeometry(id: "islandBody", namespace: namespace)

            albumArt
            waveform
            titleBlock
            progressBar
            elapsedLabel
            remainingLabel
            previousButton
            pauseButton
            nextButton
            airplayButton
        }
        .frame(width: Layout.canvasWidth, height: Layout.canvasHeight)
    }

    // MARK: - Fixed elements (top-left coordinates via .offset)

    private var albumArt: some View {
        AlbumArtView(
            image: activity.playbackState?.artwork,
            size: Layout.artSize,
            cornerRadius: DesignTokens.MusicMetrics.albumArtCornerRadius
        )
        .islandMatchedGeometry(id: "albumArt", namespace: namespace)
        .offset(x: Layout.artOrigin.x, y: Layout.artOrigin.y)
    }

    private var waveform: some View {
        Waveform(isPlaying: activity.playbackState?.isPlaying ?? false)
            .frame(width: Layout.waveformSize.width, height: Layout.waveformSize.height)
            .islandMatchedGeometry(id: "waveform", namespace: namespace)
            .offset(x: Layout.waveformOrigin.x, y: Layout.waveformOrigin.y)
    }

    /// The only dynamic layout in this view — a small leading-aligned
    /// VStack for title+artist. Fixed width; title truncates instead of
    /// ever moving or resizing anything else.
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
        .frame(width: Layout.titleWidth, alignment: .leading)
        .transition(AnimationTokens.contentTransition(insertDelay: 0.02, removeDelay: 0.04))
        .offset(x: Layout.titleOrigin.x, y: Layout.titleOrigin.y)
    }

    /// Track fill is computed directly from the known fixed track width —
    /// no `GeometryReader` measurement needed since the track's size is
    /// itself a fixed constant, not something derived at runtime.
    private var progressBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.2))
            Capsule()
                .fill(DesignTokens.Color.primaryText)
                .frame(width: Layout.progressTrackSize.width * progressFraction)
        }
        .frame(width: Layout.progressTrackSize.width, height: Layout.progressTrackSize.height)
        .transition(AnimationTokens.contentTransition(insertDelay: 0.05, removeDelay: 0.02))
        .offset(x: Layout.progressTrackOrigin.x, y: Layout.progressTrackOrigin.y)
    }

    private var elapsedLabel: some View {
        Text(formatted(activity.playbackState?.elapsed ?? 0))
            .font(.system(size: 12, weight: .regular, design: .monospaced))
            .tracking(DesignTokens.Typography.letterSpacingTight)
            .foregroundStyle(DesignTokens.Color.secondaryText)
            .transition(AnimationTokens.contentTransition(insertDelay: 0.05, removeDelay: 0.02))
            .offset(x: Layout.elapsedOrigin.x, y: Layout.elapsedOrigin.y)
    }

    private var remainingLabel: some View {
        Text("-" + formatted(remaining))
            .font(DesignTokens.Typography.timestamp.monospacedDigit())
            .tracking(DesignTokens.Typography.letterSpacingTight)
            .foregroundStyle(DesignTokens.Color.secondaryText)
            .transition(AnimationTokens.contentTransition(insertDelay: 0.05, removeDelay: 0.02))
            .offset(x: Layout.remainingOrigin.x, y: Layout.remainingOrigin.y)
    }

    // MARK: - Fixed elements (center coordinates via .position)

    private var previousButton: some View {
        PlaybackButton(systemName: "backward.fill", action: activity.skipBackward, size: 16)
            .opacity(0.7)
            .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
            .position(Layout.previousCenter)
    }

    private var pauseButton: some View {
        PlaybackButton(
            systemName: (activity.playbackState?.isPlaying ?? false) ? "pause.fill" : "play.fill",
            action: activity.togglePlayPause,
            size: 20
        )
        .frame(width: 34, height: 34)
        .background(Circle().fill(Color.white.opacity(0.14)))
        .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
        .position(Layout.pauseCenter)
    }

    private var nextButton: some View {
        PlaybackButton(systemName: "forward.fill", action: activity.skipForward, size: 16)
            .opacity(0.7)
            .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
            .position(Layout.nextCenter)
    }

    private var airplayButton: some View {
        Image(systemName: "airplayaudio")
            .font(.system(size: 18))
            .foregroundStyle(DesignTokens.Color.primaryText)
            .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
            .position(Layout.airplayCenter)
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
