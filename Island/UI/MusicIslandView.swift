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

    /// Mouse-driven glow offset.
    @State private var glowOffset: CGSize = .zero

    // MARK: - Compact album flip

    @State private var compactFlipAngle: Double = 0

    @State private var flipOldArtwork: NSImage?

    @State private var flipNewArtwork: NSImage?

    @State private var isFlippingCompactArtwork = false

    @State private var lastTrackKey = ""

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

    private var currentArtwork: NSImage? {

        activity.playbackState?.artwork
            ?? NSImage(named: "Currents")
    }

    private var trackKey: String {

        "\(activity.playbackState?.title ?? "")|\(activity.playbackState?.artist ?? "")"
    }

    // IMPORTANT:
    //
    // The entire MusicIslandView is centered by its parent.
    // When the island shrinks, its left edge moves to the right.
    //
    // Expanded-only content uses fixed expanded coordinates, so we
    // compensate for that movement while the content fades away.

    private var expandedContentCollapseOffset: CGFloat {

        isExpanded
            ? 0
            : -(expandedSize.width - compactSize.width) / 2
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
                x:
                    Metrics.compactEdgePadding
                    + Metrics.compactIconSize / 2,
                y:
                    DesignTokens.MusicMetrics
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
                x:
                    compactSize.width
                    - Metrics.compactEdgePadding
                    - Metrics.compactIconSize / 2,
                y:
                    DesignTokens.MusicMetrics
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

    // Equal spacing on both sides of pause/play.
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

            IslandShape(
                topRadius:
                    isExpanded
                    ? ShapeTokens.expandedTopRadius
                    : ShapeTokens.compactTopRadius,

                bottomRadius:
                    isExpanded
                    ? ShapeTokens.expandedBottomRadius
                    : ShapeTokens.compactBottomRadius
            )
            .fill(
                DesignTokens.Color.islandBackground
            )

            // MARK: Album

            if isExpanded {

                AlbumArtView(
                    image:
                        activity.playbackState?.artwork,
                    size:
                        artSize,
                    cornerRadius:
                        artCornerRadius,
                    showGlow:
                        true,
                    glowColor:
                        artworkColor,
                    glowOffset:
                        glowOffset
                )
                .position(artCenter)

            } else {

                compactAlbumArt
                    .frame(
                        width: artSize,
                        height: artSize
                    )
                    .position(artCenter)
            }

            // MARK: Waveform

            Waveform(
                isPlaying:
                    activity.playbackState?.isPlaying
                    ?? false,

                color:
                    artworkColor
            )
            .frame(
                width: waveformSize.width,
                height: waveformSize.height
            )
            .position(waveformCenter)

            // MARK: Expanded content

            //
            // IMPORTANT:
            //
            // All expanded-only elements remain in their normal
            // expanded coordinate positions. The entire group gets
            // compensated horizontally when collapsing so it doesn't
            // appear to jump to the right as the parent shrinks.

            ZStack(alignment: .topLeading) {

                titleBlock

                progressBar

                elapsedLabel

                remainingLabel

                previousButton

                pauseButton

                nextButton

                airplayButton
            }
            .offset(
                x:
                    expandedContentCollapseOffset
            )
        }

        .frame(
            width: currentSize.width,
            height: currentSize.height
        )

        .onContinuousHover(
            coordinateSpace: .local
        ) { phase in

            guard isExpanded else {
                return
            }

            switch phase {

            case .active(let location):

                let centerX =
                    currentSize.width / 2

                let centerY =
                    currentSize.height / 2

                let normalizedX =
                    (location.x - centerX) / centerX

                let normalizedY =
                    (location.y - centerY) / centerY

                let maxTravel: CGFloat = 8

                withAnimation(
                    .easeOut(duration: 0.12)
                ) {

                    glowOffset = CGSize(
                        width:
                            normalizedX * maxTravel,

                        height:
                            normalizedY * maxTravel
                    )
                }

            case .ended:

                withAnimation(
                    .easeOut(duration: 0.18)
                ) {

                    glowOffset = .zero
                }
            }
        }

        // MARK: Artwork color

        .task(
            id:
                activity
                .playbackState?
                .artwork?
                .tiffRepresentation
        ) {

            let artwork =
                activity.playbackState?.artwork
                ?? NSImage(named: "Currents")

            artworkColor =
                ArtworkColorExtractor.dominantColor(
                    from:
                        artwork,
                    fallback:
                        DesignTokens.Color.musicAccent
                )

            if !isFlippingCompactArtwork {

                flipNewArtwork =
                    artwork
            }
        }

        // MARK: Track change

        .onChange(of: trackKey) { _, newKey in

            guard !newKey.isEmpty else {
                return
            }

            // First song.
            if lastTrackKey.isEmpty {

                lastTrackKey =
                    newKey

                flipNewArtwork =
                    currentArtwork

                return
            }

            // Same song.
            guard newKey != lastTrackKey else {
                return
            }

            lastTrackKey =
                newKey

            let oldArtwork =
                flipNewArtwork
                ?? NSImage(named: "Currents")

            let newArtwork =
                currentArtwork
                ?? NSImage(named: "Currents")

            // If the track changes while expanded,
            // just update the stored artwork.
            //
            // The flip is ONLY a compact-view animation.
            guard !isExpanded else {

                flipNewArtwork =
                    newArtwork

                return
            }

            flipOldArtwork =
                oldArtwork

            flipNewArtwork =
                newArtwork

            isFlippingCompactArtwork =
                true

            compactFlipAngle =
                0

            withAnimation(
                .easeInOut(
                    duration: 0.42
                )
            ) {

                compactFlipAngle =
                    180
            }

            DispatchQueue.main.asyncAfter(
                deadline:
                    .now() + 0.42
            ) {

                guard
                    isFlippingCompactArtwork
                else {
                    return
                }

                flipNewArtwork =
                    newArtwork

                flipOldArtwork =
                    nil

                isFlippingCompactArtwork =
                    false

                compactFlipAngle =
                    0
            }
        }
    }

    // MARK: - Compact Album

    private var compactAlbumArt: some View {

        ZStack {

            if isFlippingCompactArtwork {

                // OLD COVER
                AlbumArtView(
                    image:
                        flipOldArtwork,
                    size:
                        artSize,
                    cornerRadius:
                        artCornerRadius,
                    showGlow:
                        false,
                    glowColor:
                        artworkColor,
                    glowOffset:
                        .zero
                )
                .frame(
                    width: artSize,
                    height: artSize
                )
                .rotation3DEffect(
                    .degrees(
                        compactFlipAngle
                    ),
                    axis: (
                        x: 0,
                        y: 1,
                        z: 0
                    ),
                    anchor:
                        .center,
                    anchorZ:
                        0,
                    perspective:
                        0.55
                )
                .opacity(
                    compactFlipAngle < 90
                        ? 1
                        : 0
                )

                // NEW COVER
                AlbumArtView(
                    image:
                        flipNewArtwork,
                    size:
                        artSize,
                    cornerRadius:
                        artCornerRadius,
                    showGlow:
                        false,
                    glowColor:
                        artworkColor,
                    glowOffset:
                        .zero
                )
                .frame(
                    width: artSize,
                    height: artSize
                )
                .rotation3DEffect(
                    .degrees(
                        compactFlipAngle - 180
                    ),
                    axis: (
                        x: 0,
                        y: 1,
                        z: 0
                    ),
                    anchor:
                        .center,
                    anchorZ:
                        0,
                    perspective:
                        0.55
                )
                .opacity(
                    compactFlipAngle >= 90
                        ? 1
                        : 0
                )

            } else {

                AlbumArtView(
                    image:
                        currentArtwork,
                    size:
                        artSize,
                    cornerRadius:
                        artCornerRadius,
                    showGlow:
                        false,
                    glowColor:
                        artworkColor,
                    glowOffset:
                        .zero
                )
                .frame(
                    width: artSize,
                    height: artSize
                )
            }
        }

        // CRITICAL:
        //
        // The flip container has the exact same size as the compact
        // artwork. Nothing inside this animation participates in the
        // island's layout.
        .frame(
            width: artSize,
            height: artSize
        )

        .clipped()
    }

    // MARK: - Expanded-only content

    // MARK: - Title

    private var titleBlock: some View {

        VStack(
            alignment: .leading,
            spacing:
                DesignTokens.Spacing.xxs
        ) {

            Text(
                activity.playbackState?.title
                ?? ""
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
                activity.playbackState?.artist
                ?? ""
            )
            .font(
                DesignTokens.Typography.subtitle
            )
            .tracking(
                DesignTokens
                    .Typography
                    .letterSpacingTight
            )
            .foregroundStyle(
                DesignTokens.Color.secondaryText
            )
            .lineLimit(1)
            .truncationMode(.tail)
        }

        .frame(
            width:
                titleWidth,
            alignment:
                .leading
        )

        .offset(
            x:
                titleOrigin.x,
            y:
                titleOrigin.y
                + (
                    isExpanded
                    ? 0
                    : -4
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.12
                : 0,
            duration:
                0.25
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
            width:
                progressSize.width,
            height:
                progressSize.height
        )

        .offset(
            x:
                progressOrigin.x,
            y:
                progressOrigin.y
                + (
                    isExpanded
                    ? 0
                    : -3
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.14
                : 0,
            duration:
                0.25
        )

        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Elapsed time

    private var elapsedLabel: some View {

        Text(
            formatted(
                activity.playbackState?.elapsed
                ?? 0
            )
        )

        .font(
            .system(
                size: 12,
                weight: .regular,
                design: .default
            )
        )

        .tracking(
            DesignTokens
                .Typography
                .letterSpacingTight
        )

        .foregroundStyle(
            DesignTokens.Color.secondaryText
        )

        .offset(
            x:
                elapsedOrigin.x,
            y:
                elapsedOrigin.y
                + (
                    isExpanded
                    ? 0
                    : -3
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.14
                : 0,
            duration:
                0.25
        )
    }

    // MARK: - Remaining time

    private var remainingLabel: some View {

        Text(
            "-" + formatted(
                remaining
            )
        )

        .font(
            .system(
                size: 12,
                weight: .regular,
                design: .default
            )
        )

        .tracking(
            DesignTokens
                .Typography
                .letterSpacingTight
        )

        .foregroundStyle(
            DesignTokens.Color.secondaryText
        )

        .offset(
            x:
                remainingOrigin.x,
            y:
                remainingOrigin.y
                + (
                    isExpanded
                    ? 0
                    : -3
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.14
                : 0,
            duration:
                0.25
        )
    }

    // MARK: - Previous button

    private var previousButton: some View {

        PlaybackButton(
            systemName:
                "backward.fill",
            action:
                activity.skipBackward,
            size:
                20
        )

        .opacity(0.7)

        .position(
            x:
                previousCenter.x,
            y:
                previousCenter.y
                + (
                    isExpanded
                    ? 0
                    : -4
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.16
                : 0,
            duration:
                0.25
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
                32
        )

        .frame(
            width: 34,
            height: 34
        )

        .position(
            x:
                pauseCenter.x,
            y:
                pauseCenter.y
                + (
                    isExpanded
                    ? 0
                    : -4
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.16
                : 0,
            duration:
                0.25
        )

        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Next button

    private var nextButton: some View {

        PlaybackButton(
            systemName:
                "forward.fill",
            action:
                activity.skipForward,
            size:
                20
        )

        .opacity(0.7)

        .position(
            x:
                nextCenter.x,
            y:
                nextCenter.y
                + (
                    isExpanded
                    ? 0
                    : -4
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.16
                : 0,
            duration:
                0.25
        )

        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - AirPlay

    private var airplayButton: some View {

        Image(
            systemName:
                "airplayaudio"
        )

        .font(
            .system(size: 18)
        )

        .foregroundStyle(
            DesignTokens.Color.primaryText
        )

        .frame(
            width:
                Metrics.airplayIconSize,
            height:
                Metrics.airplayIconSize
        )

        .position(
            x:
                airplayCenter.x,
            y:
                airplayCenter.y
                + (
                    isExpanded
                    ? 0
                    : -4
                )
        )

        .fadeOnly(
            isVisible:
                isExpanded,
            delay:
                isExpanded
                ? 0.16
                : 0,
            duration:
                0.25
        )

        .allowsHitTesting(
            isExpanded
        )
    }

    // MARK: - Derived values

    private var remaining: TimeInterval {

        max(
            (activity.playbackState?.duration ?? 0)
                - (activity.playbackState?.elapsed ?? 0),
            0
        )
    }

    private var progressFraction: CGFloat {

        guard
            let state =
                activity.playbackState,
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

// MARK: - Fade-only animation

private extension View {

    func fadeOnly(
        isVisible: Bool,
        delay: Double,
        duration: Double
    ) -> some View {

        self

            .transaction { transaction in
                transaction.animation = nil
            }

            .modifier(
                FadeOnlyModifier(
                    isVisible:
                        isVisible,
                    delay:
                        delay,
                    duration:
                        duration
                )
            )
    }
}

private struct FadeOnlyModifier:
    ViewModifier {

    let isVisible: Bool

    let delay: Double

    let duration: Double

    @State private var opacity: Double = 0

    func body(
        content: Content
    ) -> some View {

        content

            .opacity(
                opacity
            )

            .onAppear {

                opacity =
                    isVisible
                    ? 1
                    : 0
            }

            .onChange(
                of:
                    isVisible
            ) { _, newValue in

                withAnimation(
                    .easeOut(
                        duration:
                            newValue
                            ? duration
                            : 0.10
                    )
                    .delay(
                        newValue
                        ? delay
                        : 0
                    )
                ) {

                    opacity =
                        newValue
                        ? 1
                        : 0
                }
            }
    }
}
