import SwiftUI

/// The expanded, hover-triggered presentation of Music.
///
/// A fixed 390×200 canvas. Album art and waveform continue to use
/// matched geometry and are intentionally left untouched.
///
/// The remaining expanded elements use their own lightweight
/// opacity/scale/offset animation so they enter and leave smoothly
/// without fighting the island's morph animation.
struct MusicExpandedView: View {

    @ObservedObject var activity: MusicActivity

    @Environment(\.islandNamespace) private var namespace

    // MARK: - Layout

    private enum Layout {

        static let canvasWidth: CGFloat =
            DesignTokens.MusicMetrics.expandedWidth

        static let canvasHeight: CGFloat =
            DesignTokens.MusicMetrics.expandedHeight

        static let artOrigin =
            CGPoint(
                x: 24,
                y: 24
            )

        static let artSize:
            CGFloat = 65

        static let waveformOrigin =
            CGPoint(
                x: 338.85,
                y: 24
            )

        static let waveformSize =
            CGSize(
                width: 25.57,
                height: 24
            )

        static let titleOrigin =
            CGPoint(
                x: 106,
                y: 36
            )

        static let titleWidth:
            CGFloat =
                waveformOrigin.x
                - titleOrigin.x
                - 16

        static let progressTrackOrigin =
            CGPoint(
                x: 71,
                y: 112
            )

        static let progressTrackSize =
            CGSize(
                width: 242,
                height: 7
            )

        static let elapsedOrigin =
            CGPoint(
                x: 24,
                y: 106
            )

        static let remainingOrigin =
            CGPoint(
                x: 333,
                y: 106
            )

        static let rowCenterY:
            CGFloat = 159.9

        static let pauseCenter =
            CGPoint(
                x:
                    canvasWidth / 2,

                y:
                    rowCenterY
            )

        static let previousCenter =
            CGPoint(
                x:
                    pauseCenter.x
                    - DesignTokens
                        .MusicMetrics
                        .playbackButtonSpacing,

                y:
                    rowCenterY
            )

        static let nextCenter =
            CGPoint(
                x:
                    pauseCenter.x
                    + DesignTokens
                        .MusicMetrics
                        .playbackButtonSpacing,

                y:
                    rowCenterY
            )

        static let airplayIconSize:
            CGFloat = 23

        static let airplayCenter =
            CGPoint(
                x: 335.5,
                y: 159.9
            )
    }

    // MARK: - Animation

    /// Small, deliberately independent animation for the elements
    /// other than album art and waveform.
    ///
    /// We do NOT use `.transition()` here because the expanded view
    /// itself remains mounted during the island morph.
    private let elementAnimation =
        Animation.easeOut(
            duration: 0.20
        )

    // MARK: - Body

    var body: some View {

        ZStack(
            alignment:
                .topLeading
        ) {

            // =========================================================
            // ISLAND
            //
            // UNTOUCHED.
            // =========================================================

            IslandShape(
                topRadius:
                    DesignTokens
                        .Shape
                        .expandedTopRadius,

                bottomRadius:
                    DesignTokens
                        .Shape
                        .expandedBottomRadius
            )
            .fill(
                DesignTokens
                    .Color
                    .islandBackground
            )
            .islandMatchedGeometry(
                id:
                    "islandBody",

                namespace:
                    namespace
            )

            // =========================================================
            // ALBUM
            //
            // UNTOUCHED.
            // =========================================================

            albumArt

            // =========================================================
            // WAVEFORM
            //
            // UNTOUCHED.
            // =========================================================

            waveform

            // =========================================================
            // OTHER ELEMENTS
            // =========================================================

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
            width:
                Layout.canvasWidth,

            height:
                Layout.canvasHeight
        )
    }

    // MARK: - Album

    private var albumArt: some View {

        AlbumArtView(
            image:
                activity
                    .playbackState?
                    .artwork,

            size:
                Layout.artSize,

            cornerRadius:
                DesignTokens
                    .MusicMetrics
                    .albumArtCornerRadius
        )
        .islandMatchedGeometry(
            id:
                "albumArt",

            namespace:
                namespace
        )
        .offset(
            x:
                Layout.artOrigin.x,

            y:
                Layout.artOrigin.y
        )
    }

    // MARK: - Waveform

    private var waveform: some View {

        Waveform(
            isPlaying:
                activity
                    .playbackState?
                    .isPlaying
                ?? false
        )
        .frame(
            width:
                Layout.waveformSize.width,

            height:
                Layout.waveformSize.height
        )
        .islandMatchedGeometry(
            id:
                "waveform",

            namespace:
                namespace
        )
        .offset(
            x:
                Layout.waveformOrigin.x,

            y:
                Layout.waveformOrigin.y
        )
    }

    // MARK: - Title

    private var titleBlock: some View {

        VStack(
            alignment:
                .leading,

            spacing:
                DesignTokens
                    .Spacing
                    .xxs
        ) {

            Text(
                activity
                    .playbackState?
                    .title
                ?? ""
            )
            .font(
                DesignTokens
                    .Typography
                    .title
            )
            .foregroundStyle(
                DesignTokens
                    .Color
                    .primaryText
            )
            .lineLimit(
                1
            )
            .truncationMode(
                .tail
            )

            Text(
                activity
                    .playbackState?
                    .artist
                ?? ""
            )
            .font(
                DesignTokens
                    .Typography
                    .subtitle
            )
            .tracking(
                DesignTokens
                    .Typography
                    .letterSpacingTight
            )
            .foregroundStyle(
                DesignTokens
                    .Color
                    .secondaryText
            )
            .lineLimit(
                1
            )
            .truncationMode(
                .tail
            )
        }

        .frame(
            width:
                Layout.titleWidth,

            alignment:
                .leading
        )

        .expandedElementAnimation(
            offset:
                7,

            scale:
                0.985,

            animation:
                elementAnimation
        )

        .offset(
            x:
                Layout.titleOrigin.x,

            y:
                Layout.titleOrigin.y
        )
    }

    // MARK: - Progress Bar

    private var progressBar: some View {

        ZStack(
            alignment:
                .leading
        ) {

            Capsule()
                .fill(
                    Color.white.opacity(
                        0.2
                    )
                )

            Capsule()
                .fill(
                    DesignTokens
                        .Color
                        .primaryText
                )
                .frame(
                    width:
                        Layout
                            .progressTrackSize
                            .width
                        * progressFraction
                )
        }

        .frame(
            width:
                Layout
                    .progressTrackSize
                    .width,

            height:
                Layout
                    .progressTrackSize
                    .height
        )

        .expandedElementAnimation(
            offset:
                5,

            scale:
                0.99,

            animation:
                elementAnimation
        )

        .offset(
            x:
                Layout
                    .progressTrackOrigin
                    .x,

            y:
                Layout
                    .progressTrackOrigin
                    .y
        )
    }

    // MARK: - Elapsed

    private var elapsedLabel: some View {

        Text(
            formatted(
                activity
                    .playbackState?
                    .elapsed
                ?? 0
            )
        )
        .font(
            .system(
                size:
                    12,

                weight:
                    .regular,

                design:
                    .monospaced
            )
        )
        .tracking(
            DesignTokens
                .Typography
                .letterSpacingTight
        )
        .foregroundStyle(
            DesignTokens
                .Color
                .secondaryText
        )

        .expandedElementAnimation(
            offset:
                5,

            scale:
                0.99,

            animation:
                elementAnimation
        )

        .offset(
            x:
                Layout
                    .elapsedOrigin
                    .x,

            y:
                Layout
                    .elapsedOrigin
                    .y
        )
    }

    // MARK: - Remaining

    private var remainingLabel: some View {

        Text(
            "-"
            + formatted(
                remaining
            )
        )
        .font(
            DesignTokens
                .Typography
                .timestamp
                .monospacedDigit()
        )
        .tracking(
            DesignTokens
                .Typography
                .letterSpacingTight
        )
        .foregroundStyle(
            DesignTokens
                .Color
                .secondaryText
        )

        .expandedElementAnimation(
            offset:
                5,

            scale:
                0.99,

            animation:
                elementAnimation
        )

        .offset(
            x:
                Layout
                    .remainingOrigin
                    .x,

            y:
                Layout
                    .remainingOrigin
                    .y
        )
    }

    // MARK: - Previous

    private var previousButton: some View {

        PlaybackButton(
            systemName:
                "backward.fill",

            action:
                activity.skipBackward,

            size:
                16
        )
        .opacity(
            0.7
        )

        .expandedElementAnimation(
            offset:
                6,

            scale:
                0.92,

            animation:
                elementAnimation
        )

        .position(
            Layout.previousCenter
        )
    }

    // MARK: - Pause

    private var pauseButton: some View {

        PlaybackButton(
            systemName:
                (
                    activity
                        .playbackState?
                        .isPlaying
                    ?? false
                )
                ? "pause.fill"
                : "play.fill",

            action:
                activity.togglePlayPause,

            size:
                20
        )

        .expandedElementAnimation(
            offset:
                6,

            scale:
                0.92,

            animation:
                elementAnimation
        )

        .position(
            Layout.pauseCenter
        )
    }

    // MARK: - Next

    private var nextButton: some View {

        PlaybackButton(
            systemName:
                "forward.fill",

            action:
                activity.skipForward,

            size:
                16
        )
        .opacity(
            0.7
        )

        .expandedElementAnimation(
            offset:
                6,

            scale:
                0.92,

            animation:
                elementAnimation
        )

        .position(
            Layout.nextCenter
        )
    }

    // MARK: - AirPlay

    private var airplayButton: some View {

        Image(
            systemName:
                "airplayaudio"
        )
        .font(
            .system(
                size:
                    18
            )
        )
        .foregroundStyle(
            DesignTokens
                .Color
                .primaryText
        )
        .frame(
            width:
                DesignTokens
                    .MusicMetrics
                    .airplayIconSize,

            height:
                DesignTokens
                    .MusicMetrics
                    .airplayIconSize
        )

        .expandedElementAnimation(
            offset:
                6,

            scale:
                0.92,

            animation:
                elementAnimation
        )

        .position(
            Layout.airplayCenter
        )
    }

    // MARK: - Derived Values

    private var remaining:
        TimeInterval {

        max(
            (
                activity
                    .playbackState?
                    .duration
                ?? 0
            )
            -
            (
                activity
                    .playbackState?
                    .elapsed
                ?? 0
            ),

            0
        )
    }

    private var progressFraction:
        CGFloat {

        guard
            let state =
                activity.playbackState,

            state.duration > 0
        else {
            return 0
        }

        return min(
            max(
                state.elapsed
                / state.duration,

                0
            ),

            1
        )
    }

    private func formatted(
        _ interval:
            TimeInterval
    ) -> String {

        let total =
            max(
                Int(interval),
                0
            )

        return String(
            format:
                "%d:%02d",

            total / 60,

            total % 60
        )
    }
}

// MARK: - Expanded Element Animation

private extension View {

    func expandedElementAnimation(
        offset:
            CGFloat,

        scale:
            CGFloat,

        animation:
            Animation
    ) -> some View {

        modifier(
            ExpandedElementModifier(
                offset:
                    offset,

                scale:
                    scale,

                animation:
                    animation
            )
        )
    }
}

private struct ExpandedElementModifier:
    ViewModifier {

    let offset:
        CGFloat

    let scale:
        CGFloat

    let animation:
        Animation

    @State private var isVisible =
        false

    func body(
        content:
            Content
    ) -> some View {

        content

            .opacity(
                isVisible
                ? 1
                : 0
            )

            .scaleEffect(
                isVisible
                ? 1
                : scale,

                anchor:
                    .center
            )

            .offset(
                y:
                    isVisible
                    ? 0
                    : offset
            )

            .onAppear {

                isVisible =
                    false

                DispatchQueue.main.async {

                    withAnimation(
                        animation
                    ) {

                        isVisible =
                            true
                    }
                }
            }
    }
}
