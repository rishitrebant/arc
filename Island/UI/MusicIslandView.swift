import SwiftUI

/// Music's single island presentation — compact and expanded are NOT two
/// separate views being swapped anymore, just one view's parameters
/// changing under `isExpanded`.

struct MusicIslandView: View {

    @ObservedObject var activity: MusicActivity

    var isExpanded: Bool

    // MARK: - Artwork / Glow

    @State private var artworkColor: Color =
        DesignTokens.Color.musicAccent

    @State private var glowOffset: CGSize = .zero

    // MARK: - Album Flip

    /// The artwork currently shown on the front.
    @State private var displayedArtwork: NSImage?

    /// The real incoming artwork shown on the back.
    @State private var incomingArtwork: NSImage?

    /// Current rotation of the physical album card.
    @State private var albumFlipAngle: Double = 0

    /// True while the physical card is rotating.
    @State private var isFlippingAlbum = false

    /// Last track that we have seen.
    @State private var lastTrackKey = ""

    /// Track that is waiting for its real artwork.
    @State private var pendingTrackKey: String?

    /// Direction that belongs to the pending track change.
    ///
    /// +1 = next / forward
    /// -1 = previous / backward
    @State private var pendingFlipDirection: Double = 1

    /// Prevents duplicate flips for the same track.
    @State private var lastStartedFlipTrackKey: String?

    /// Last artwork fingerprint that we accepted.
    @State private var lastArtworkFingerprint: Data?

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

    // MARK: - Artwork

    /// Only REAL backend artwork.
    ///
    /// There is intentionally no Currents fallback.
    private var realArtwork: NSImage? {
        activity.playbackState?.artwork
    }

    /// Only artwork that has actually arrived from the playback backend.
    /// When artwork is unavailable, no placeholder album is rendered.
    private var normalArtwork: NSImage? {
        displayedArtwork
    }

    // MARK: - Track

    private var trackKey: String {
        "\(activity.playbackState?.title ?? "")|\(activity.playbackState?.artist ?? "")"
    }

    // MARK: - Artwork Fingerprint

    private var currentArtworkFingerprint: Data? {
        realArtwork?.tiffRepresentation
    }

    // MARK: - Collapse compensation

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
                x:
                    338.85
                    + 25.57 / 2,
                y:
                    24
                    + 24 / 2
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
        338.85
        - titleOrigin.x
        - 16
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

    private let playbackButtonSpacing: CGFloat = 70

    private var pauseCenter: CGPoint {
        CGPoint(
            x: expandedSize.width / 2,
            y: rowCenterY
        )
    }

    private var previousCenter: CGPoint {
        CGPoint(
            x:
                pauseCenter.x
                - playbackButtonSpacing,
            y:
                rowCenterY
        )
    }

    private var nextCenter: CGPoint {
        CGPoint(
            x:
                pauseCenter.x
                + playbackButtonSpacing,
            y:
                rowCenterY
        )
    }

    private let airplayCenter = CGPoint(
        x: 335.5,
        y: 159.9
    )

    // MARK: - Body

    var body: some View {

        ZStack(
            alignment: .topLeading
        ) {

            // MARK: Island background

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

            albumArtView
                .position(
                    artCenter
                )

            // MARK: Waveform

            Waveform(
                isPlaying:
                    activity
                        .playbackState?
                        .isPlaying
                    ?? false,

                color:
                    artworkColor
            )
            .frame(
                width:
                    waveformSize.width,

                height:
                    waveformSize.height
            )
            .position(
                waveformCenter
            )

            // MARK: Expanded content

            ZStack(
                alignment:
                    .topLeading
            ) {

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
            width:
                currentSize.width,

            height:
                currentSize.height
        )

        // MARK: Hover glow

        .onContinuousHover(
            coordinateSpace:
                .local
        ) { phase in

            guard
                isExpanded
            else {
                return
            }

            switch phase {

            case .active(
                let location
            ):

                let centerX =
                    currentSize.width / 2

                let centerY =
                    currentSize.height / 2

                let normalizedX =
                    (
                        location.x
                        - centerX
                    )
                    / centerX

                let normalizedY =
                    (
                        location.y
                        - centerY
                    )
                    / centerY

                let maxTravel:
                    CGFloat = 8

                withAnimation(
                    .easeOut(
                        duration:
                            0.12
                    )
                ) {

                    glowOffset =
                        CGSize(
                            width:
                                normalizedX
                                * maxTravel,

                            height:
                                normalizedY
                                * maxTravel
                        )
                }

            case .ended:

                withAnimation(
                    .easeOut(
                        duration:
                            0.18
                    )
                ) {

                    glowOffset =
                        .zero
                }
            }
        }

        // MARK: Artwork color

        .task(
            id:
                currentArtworkFingerprint
        ) {

            if let colorArtwork =
                realArtwork
            {

                artworkColor =
                    ArtworkColorExtractor.dominantColor(
                        from:
                            colorArtwork,

                        fallback:
                            DesignTokens.Color.musicAccent
                    )

            } else {

                artworkColor =
                    DesignTokens.Color.musicAccent
            }
        }

        // MARK: REAL artwork arrival

        .onChange(
            of:
                currentArtworkFingerprint
        ) { _, newFingerprint in

            guard
                let newFingerprint,

                let newArtwork =
                    realArtwork

            else {
                return
            }

            // Ignore the exact same artwork.

            if
                lastArtworkFingerprint
                    == newFingerprint
            {
                return
            }

            lastArtworkFingerprint =
                newFingerprint

            // ---------------------------------------------------------
            // FIRST ARTWORK
            // ---------------------------------------------------------

            if displayedArtwork == nil {

                displayedArtwork =
                    newArtwork

                incomingArtwork =
                    nil

                return
            }

            // ---------------------------------------------------------
            // A NEW TRACK IS WAITING
            // ---------------------------------------------------------

            if
                let pendingTrackKey,

                pendingTrackKey
                    == trackKey,

                pendingTrackKey
                    != lastStartedFlipTrackKey
            {

                startAlbumFlip(
                    to:
                        newArtwork,

                    artworkFingerprint:
                        newFingerprint,

                    trackKey:
                        pendingTrackKey
                )

                return
            }

            // ---------------------------------------------------------
            // NORMAL ARTWORK UPDATE
            // ---------------------------------------------------------

            if !isFlippingAlbum {

                displayedArtwork =
                    newArtwork

                incomingArtwork =
                    nil
            }
        }

        // MARK: Track change

        .onChange(
            of:
                trackKey
        ) { _, newKey in

            guard
                !newKey.isEmpty
            else {
                return
            }

            // ---------------------------------------------------------
            // First track.
            // ---------------------------------------------------------

            if lastTrackKey.isEmpty {

                lastTrackKey =
                    newKey

                pendingTrackKey =
                    nil

                if let artwork =
                    realArtwork
                {

                    displayedArtwork =
                        artwork

                    lastArtworkFingerprint =
                        artwork
                            .tiffRepresentation
                }

                return
            }

            // Same track.

            guard
                newKey != lastTrackKey
            else {
                return
            }

            lastTrackKey =
                newKey

            // ---------------------------------------------------------
            // DO NOT flip yet.
            //
            // The metadata can arrive before the new artwork.
            // Keep the direction alive until the real artwork arrives.
            // ---------------------------------------------------------

            pendingTrackKey =
                newKey
        }
    }

    // MARK: - Album Art

    private var albumArtView: some View {

        ZStack {

            if isFlippingAlbum {

                // =====================================================
                // FRONT
                // =====================================================

                AlbumArtView(
                    image:
                        displayedArtwork,

                    size:
                        artSize,

                    cornerRadius:
                        artCornerRadius,

                    showGlow:
                        isExpanded,

                    glowColor:
                        artworkColor,

                    glowOffset:
                        isExpanded
                        ? glowOffset
                        : .zero
                )

                .frame(
                    width:
                        artSize,

                    height:
                        artSize
                )

                .rotation3DEffect(
                    .degrees(
                        albumFlipAngle
                    ),

                    axis:
                        (
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
                    abs(
                        albumFlipAngle
                    ) < 90
                    ? 1
                    : 0
                )

                // =====================================================
                // BACK
                // =====================================================

                AlbumArtView(
                    image:
                        incomingArtwork,

                    size:
                        artSize,

                    cornerRadius:
                        artCornerRadius,

                    showGlow:
                        isExpanded,

                    glowColor:
                        artworkColor,

                    glowOffset:
                        isExpanded
                        ? glowOffset
                        : .zero
                )

                .frame(
                    width:
                        artSize,

                    height:
                        artSize
                )

                .rotation3DEffect(
                    .degrees(
                        180
                        + albumFlipAngle
                    ),

                    axis:
                        (
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
                    abs(
                        albumFlipAngle
                    ) >= 90
                    ? 1
                    : 0
                )

            } else if let artwork =
                        normalArtwork {

                // =====================================================
                // NORMAL
                // =====================================================

                AlbumArtView(
                    image:
                        artwork,

                    size:
                        artSize,

                    cornerRadius:
                        artCornerRadius,

                    showGlow:
                        isExpanded,

                    glowColor:
                        artworkColor,

                    glowOffset:
                        isExpanded
                        ? glowOffset
                        : .zero
                )

                .frame(
                    width:
                        artSize,

                    height:
                        artSize
                )
            }
        }

        // IMPORTANT:
        // The album card itself stays exactly the same size.
        // NO `.clipped()` here.

        .frame(
            width:
                artSize,

            height:
                artSize
        )
    }

    // MARK: - Start Album Flip

    private func startAlbumFlip(
        to newArtwork:
            NSImage,

        artworkFingerprint:
            Data,

        trackKey:
            String
    ) {

        // Don't interrupt an existing flip.

        guard
            !isFlippingAlbum
        else {
            return
        }

        // We need a real current front.

        guard
            displayedArtwork != nil
        else {

            displayedArtwork =
                newArtwork

            incomingArtwork =
                nil

            pendingTrackKey =
                nil

            lastStartedFlipTrackKey =
                trackKey

            lastArtworkFingerprint =
                artworkFingerprint

            return
        }

        // -------------------------------------------------------------
        // REAL NEW ARTWORK GOES ON THE BACK.
        // Currents is never allowed here.
        // -------------------------------------------------------------

        incomingArtwork =
            newArtwork

        pendingTrackKey =
            nil

        lastStartedFlipTrackKey =
            trackKey

        isFlippingAlbum =
            true

        // Always start from zero.

        albumFlipAngle =
            0

        // -------------------------------------------------------------
        // PHYSICAL CARD ROTATION
        //
        // Next:
        //      0° → +180°
        //
        // Previous:
        //      0° → -180°
        // -------------------------------------------------------------

        withAnimation(
            .easeInOut(
                duration:
                    0.42
            )
        ) {

            albumFlipAngle =
                180
                * pendingFlipDirection
        }

        DispatchQueue.main.asyncAfter(
            deadline:
                .now()
                + 0.42
        ) {

            guard
                self.isFlippingAlbum
            else {
                return
            }

            // The back face is now the front.

            self.displayedArtwork =
                newArtwork

            self.incomingArtwork =
                nil

            self.isFlippingAlbum =
                false

            self.albumFlipAngle =
                0

            self.lastArtworkFingerprint =
                artworkFingerprint
        }
    }

    // MARK: - Track Navigation

    private func skipForwardWithFlip() {

        pendingFlipDirection =
            1

        activity.skipForward()
    }

    private func skipBackwardWithFlip() {

        pendingFlipDirection =
            -1

        activity.skipBackward()
    }

    // MARK: - Title

    private var titleBlock: some View {

        VStack(
            alignment:
                .leading,

            spacing:
                DesignTokens.Spacing.xxs
        ) {

            Text(
                activity
                    .playbackState?
                    .title
                ?? ""
            )
            .font(
                DesignTokens.Typography.title
            )
            .foregroundStyle(
                DesignTokens.Color.primaryText
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
            .lineLimit(
                1
            )
            .truncationMode(
                .tail
            )
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
                    .default
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

    // MARK: - Remaining

    private var remainingLabel: some View {

        Text(
            "-"
            + formatted(
                remaining
            )
        )

        .font(
            .system(
                size:
                    12,

                weight:
                    .regular,

                design:
                    .default
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
                skipBackwardWithFlip,

            size:
                20
        )

        .opacity(
            0.7
        )

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
            width:
                34,

            height:
                34
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
                skipForwardWithFlip,

            size:
                20
        )

        .opacity(
            0.7
        )

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
            .system(
                size:
                    18
            )
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

// MARK: - Fade-only animation

private extension View {

    func fadeOnly(
        isVisible:
            Bool,

        delay:
            Double,

        duration:
            Double
    ) -> some View {

        self
            .transaction { transaction in

                transaction.animation =
                    nil
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

    let isVisible:
        Bool

    let delay:
        Double

    let duration:
        Double

    @State private var opacity:
        Double = 0

    func body(
        content:
            Content
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
