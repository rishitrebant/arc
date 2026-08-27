import SwiftUI

/// Music's single island presentation — compact and expanded are NOT two
/// separate views being swapped anymore, just one view's parameters
/// changing under `isExpanded`.
struct MusicIslandView: View {

    @ObservedObject var activity: MusicActivity
    var isExpanded: Bool

    /// The album art's dominant color, extracted once per artwork change
    /// and shared by both the glow AND the waveform.
    @State private var artworkColor: Color =
        DesignTokens.Color.musicAccent

    private typealias Metrics = DesignTokens.MusicMetrics
    private typealias ShapeTokens = DesignTokens.Shape

    // MARK: - Sizes

    private var compactSize: CGSize {
        CGSize(
            width: Metrics.compactWidth,
            height: Metrics.compactHeight
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: Metrics.expandedWidth,
            height: Metrics.expandedHeight
        )
    }

    private var currentSize: CGSize {
        isExpanded
            ? expandedSize
            : compactSize
    }

    // MARK: - Shared elements

    private var artSize: CGFloat {
        isExpanded
            ? 65
            : Metrics.compactIconSize
    }

    private var artCornerRadius: CGFloat {
        isExpanded
            ? Metrics.albumArtCornerRadius
            : Metrics.compactIconCornerRadius
    }

    private var artCenter: CGPoint {
        isExpanded
            ? CGPoint(
                x: 24 + 65 / 2,
                y: 24 + 65 / 2
            )
            : CGPoint(
                x: Metrics.compactEdgePadding
                    + Metrics.compactIconSize / 2,
                y: DesignTokens.MusicMetrics
                    .compactContentCenterY
            )
    }

    private var waveformSize: CGSize {
        isExpanded
            ? CGSize(
                width: 25.57,
                height: 24
            )
            : CGSize(
                width: Metrics.compactIconSize,
                height: Metrics.compactIconSize
            )
    }

    private var waveformCenter: CGPoint {
        isExpanded
            ? CGPoint(
                x: 338.85 + 25.57 / 2,
                y: 24 + 24 / 2
            )
            : CGPoint(
                x: compactSize.width
                    - Metrics.compactEdgePadding
                    - Metrics.compactIconSize / 2,
                y: DesignTokens.MusicMetrics
                    .compactContentCenterY
            )
    }

    // MARK: - Expanded-only layout

    private let titleOrigin = CGPoint(
        x: 106,
        y: 36
    )

    private var titleWidth: CGFloat {
        338.85 - titleOrigin.x - 16
    }

    private let progressOrigin = CGPoint(
        x: 71,
        y: 112
    )

    private let progressSize = CGSize(
        width: 242,
        height: 7
    )

    private let elapsedOrigin = CGPoint(
        x: 24,
        y: 106
    )

    private let remainingOrigin = CGPoint(
        x: 333,
        y: 106
    )

    private let rowCenterY: CGFloat = 159.9

    // MARK: - Playback spacing
    //
    // Both previous and next use this exact same value,
    // so they remain perfectly symmetrical around pause/play.

    private let playbackButtonSpacing: CGFloat = 70

    private var pauseCenter: CGPoint {
        CGPoint(
            x: expandedSize.width / 2,
            y: rowCenterY
        )
    }

    private var previousCenter: CGPoint {
        CGPoint(
            x: pauseCenter.x - playbackButtonSpacing,
            y: rowCenterY
        )
    }

    private var nextCenter: CGPoint {
        CGPoint(
            x: pauseCenter.x + playbackButtonSpacing,
            y: rowCenterY
        )
    }

    private let airplayCenter = CGPoint(
        x: 335.5,
        y: 159.9
    )

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topLeading) {

            // MARK: Island

            IslandShape(
                topRadius: isExpanded
                    ? ShapeTokens.expandedTopRadius
                    : ShapeTokens.compactTopRadius,
                bottomRadius: isExpanded
                    ? ShapeTokens.expandedBottomRadius
                    : ShapeTokens.compactBottomRadius
            )
            .fill(
                DesignTokens.Color.islandBackground
            )

            // MARK: Album

            AlbumArtView(
                image: activity.playbackState?.artwork,
                size: artSize,
                cornerRadius: artCornerRadius,
                showGlow: isExpanded,
                glowColor: artworkColor
            )
            .position(artCenter)

            // MARK: Waveform

            Waveform(
                isPlaying:
                    activity.playbackState?.isPlaying ?? false,
                color: artworkColor
            )
            .frame(
                width: waveformSize.width,
                height: waveformSize.height
            )
            .position(waveformCenter)

            // MARK: Expanded-only content

            titleBlock
            progressBar
            elapsedLabel
            remainingLabel
            previousButton
            pauseButton
            nextButton
            airplayButton
        }
        .frame(
            width: currentSize.width,
            height: currentSize.height
        )

        // MARK: Artwork colour extraction

        .task(
            id: activity.playbackState?.artwork?.tiffRepresentation
        ) {
            let artwork =
                activity.playbackState?.artwork
                ?? NSImage(named: "Currents")

            artworkColor =
                ArtworkColorExtractor.dominantColor(
                    from: artwork,
                    fallback: DesignTokens.Color.musicAccent
                )
        }
    }

    // MARK: - Expanded-only content

    private let entranceOffsetY: CGFloat = 14

    // MARK: - Title

    private var titleBlock: some View {
        VStack(
            alignment: .leading,
            spacing: DesignTokens.Spacing.xxs
        ) {
            Text(
                activity.playbackState?.title ?? ""
            )
            .font(
                DesignTokens.Typography.title
            )
            .foregroundStyle(
                DesignTokens.Color.primaryText
            )
            .lineLimit(1)
            .truncationMode(.tail)

            Text(
                activity.playbackState?.artist ?? ""
            )
            .font(
                DesignTokens.Typography.subtitle
            )
            .tracking(
                DesignTokens.Typography.letterSpacingTight
            )
            .foregroundStyle(
                DesignTokens.Color.secondaryText
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .frame(
            width: titleWidth,
            alignment: .leading
        )
        .offset(
            x: titleOrigin.x,
            y: titleOrigin.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.02 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        ZStack(alignment: .leading) {

            Capsule()
                .fill(
                    Color.white.opacity(0.2)
                )

            Capsule()
                .fill(
                    DesignTokens.Color.primaryText
                )
                .frame(
                    width:
                        progressSize.width
                        * progressFraction
                )
        }
        .frame(
            width: progressSize.width,
            height: progressSize.height
        )
        .offset(
            x: progressOrigin.x,
            y: progressOrigin.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.05 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Elapsed time

    private var elapsedLabel: some View {
        Text(
            formatted(
                activity.playbackState?.elapsed ?? 0
            )
        )
        .font(
            .system(
                size: 12,
                weight: .regular,
                design: .monospaced
            )
        )
        .tracking(
            DesignTokens.Typography.letterSpacingTight
        )
        .foregroundStyle(
            DesignTokens.Color.secondaryText
        )
        .offset(
            x: elapsedOrigin.x,
            y: elapsedOrigin.y
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.05 : 0
                ),
            value: isExpanded
        )
    }

    // MARK: - Remaining time

    private var remainingLabel: some View {
        Text(
            "-" + formatted(remaining)
        )
        .font(
            DesignTokens.Typography.timestamp
                .monospacedDigit()
        )
        .tracking(
            DesignTokens.Typography.letterSpacingTight
        )
        .foregroundStyle(
            DesignTokens.Color.secondaryText
        )
        .offset(
            x: remainingOrigin.x,
            y: remainingOrigin.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.05 : 0
                ),
            value: isExpanded
        )
    }

    // MARK: - Previous button

    private var previousButton: some View {
        PlaybackButton(
            systemName: "backward.fill",
            action: activity.skipBackward,
            size: 20
        )
        .opacity(0.7)
        .position(
            x: previousCenter.x,
            y: previousCenter.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.08 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Pause / Play

    private var pauseButton: some View {
        PlaybackButton(
            systemName:
                (
                    activity.playbackState?.isPlaying
                    ?? false
                )
                ? "pause.fill"
                : "play.fill",
            action: activity.togglePlayPause,
            size: 32
        )
        .frame(
            width: 34,
            height: 34
        )
        .position(
            x: pauseCenter.x,
            y: pauseCenter.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.08 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Next button

    private var nextButton: some View {
        PlaybackButton(
            systemName: "forward.fill",
            action: activity.skipForward,
            size: 20
        )
        .opacity(0.7)
        .position(
            x: nextCenter.x,
            y: nextCenter.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.08 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - AirPlay

    private var airplayButton: some View {
        Image(
            systemName: "airplayaudio"
        )
        .font(
            .system(size: 18)
        )
        .foregroundStyle(
            DesignTokens.Color.primaryText
        )
        .frame(
            width: Metrics.airplayIconSize,
            height: Metrics.airplayIconSize
        )
        .position(
            x: airplayCenter.x,
            y: airplayCenter.y
                + (isExpanded ? 0 : entranceOffsetY)
        )
        .opacity(
            isExpanded ? 1 : 0
        )
        .animation(
            AnimationTokens.shapeSpring
                .delay(
                    isExpanded ? 0.08 : 0
                ),
            value: isExpanded
        )
        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Derived values

    private var remaining: TimeInterval {
        max(
            (
                activity.playbackState?.duration
                ?? 0
            )
            -
            (
                activity.playbackState?.elapsed
                ?? 0
            ),
            0
        )
    }

    private var progressFraction: CGFloat {
        guard
            let state = activity.playbackState,
            state.duration > 0
        else {
            return 0
        }

        return min(
            max(
                state.elapsed / state.duration,
                0
            ),
            1
        )
    }

    private func formatted(
        _ interval: TimeInterval
    ) -> String {
        let total = max(
            Int(interval),
            0
        )

        return String(
            format: "%d:%02d",
            total / 60,
            total % 60
        )
    }
}
