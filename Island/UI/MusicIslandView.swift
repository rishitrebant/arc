import SwiftUI

/// Music's single island presentation.

///

/// Compact and expanded are NOT separate views.

/// The same view changes under `isExpanded`.

struct MusicIslandView: View {

    @ObservedObject var activity: MusicActivity

    var isExpanded: Bool

    @StateObject private var outputDeviceManager = AudioOutputDeviceManager()
    @State private var uiIsPlaying = false

    // MARK: - Skip Button "Leapfrog" Animation
    //
    // Each increments by 1 on every tap. `SkipChevrons` reads this to
    // cycle its three chevrons through a 4-slot conveyor (hidden-behind →
    // rear → front → hidden-ahead), matching the Apple Music / Dynamic
    // Island transport-button animation. Kept as two separate counters
    // since previous/next are independent gestures.
    @State private var backwardSkipTrigger = 0
    @State private var forwardSkipTrigger = 0

    // MARK: - Artwork / Waveform Color

    /// Colour used by the waveform.

    ///

    /// This can update as soon as new artwork arrives.

    @State private var artworkColor: Color =

        DesignTokens.Color.musicAccent

    /// Colour belonging to the artwork that is CURRENTLY

    /// visible on the album.

    ///

    /// IMPORTANT:

    /// This is deliberately separate from `artworkColor`.

    ///

    /// `artworkColor` can change before the album flip finishes,

    /// but `displayedArtworkColor` only changes when the artwork

    /// actually becomes the front face.

    @State private var displayedArtworkColor: Color =

        DesignTokens.Color.musicAccent

    @State private var glowOffset: CGSize = .zero

    // MARK: - Album Flip

    /// Artwork currently visible on the front.

    @State private var displayedArtwork: NSImage?

    /// New artwork temporarily placed on the back.

    @State private var incomingArtwork: NSImage?

    /// Current physical rotation.

    @State private var albumFlipAngle: Double = 0

    /// True while the album is physically flipping.

    @State private var isFlippingAlbum = false

    /// Last track observed.

    @State private var lastTrackKey = ""

    /// Track waiting for its artwork.

    @State private var pendingTrackKey: String?

    /// +1 = next

    /// -1 = previous

    @State private var pendingFlipDirection: Double = 1

    /// Prevent duplicate flips for the same track.

    @State private var lastStartedFlipTrackKey: String?

    /// Last artwork fingerprint accepted.

    @State private var lastArtworkFingerprint: Data?

    // MARK: - Interactive Progress

    @State private var isSeeking =

        false

    @State private var seekPreviewElapsed:

        TimeInterval = 0

    private typealias Metrics =

        DesignTokens.MusicMetrics

    private typealias ShapeTokens =

        DesignTokens.Shape

    // MARK: - Sizes

    private var compactSize: CGSize {

        CGSize(

            width:

                Metrics.compactWidth,

            height:

                Metrics.compactHeight

        )

    }

    private var expandedSize: CGSize {

        CGSize(

            width:

                Metrics.expandedWidth,

            height:

                Metrics.expandedHeight

        )

    }

    private var currentSize: CGSize {

        isExpanded

            ? expandedSize

            : compactSize

    }

    // MARK: - Artwork

    /// Only real artwork from MediaRemote.

    ///

    /// Currents is never used as incoming artwork.

    private var realArtwork: NSImage? {

        activity

            .playbackState?

            .artwork

    }

    /// Artwork shown when we are not currently flipping.

    ///

    /// The real backend artwork is preferred.

    private var normalArtwork: NSImage {

        displayedArtwork

            ?? NSImage(named: "Currents")

            ?? NSImage()

    }

    // MARK: - Track

    private var trackKey: String {

        "\(activity.playbackState?.title ?? "")|\(activity.playbackState?.artist ?? "")"

    }

    // MARK: - Artwork Fingerprint

    private var currentArtworkFingerprint: Data? {

        realArtwork?

            .tiffRepresentation

    }

    // MARK: - Shared Elements

    private var artSize: CGFloat {

        let base: CGFloat =
            isExpanded
                ? 65
                : Metrics.compactIconSize

        // Paused: album art shrinks slightly. Expanded gets a clearly
        // noticeable shrink; compact — per spec — gets a MUCH smaller
        // one, since there's very little room to work with there and a
        // shrink of the same magnitude would just look like a glitch.
        let pausedShrink: CGFloat =
            isExpanded
                ? 10
                : 2

        return uiIsPlaying
            ? base
            : base - pausedShrink

    }

    /// Paused: album art fades down slightly (glow — see `showGlow`
    /// below — is handled separately since it's a fully separate visual
    /// layer, not just opacity). Expanded fades more noticeably than
    /// compact, matching the size-shrink asymmetry above.
    private var artOpacity: Double {

        if uiIsPlaying { return 1 }

        return isExpanded
            ? 0.6
            : 0.85

    }

    private var artCornerRadius: CGFloat {

        isExpanded

            ? Metrics.albumArtCornerRadius

            : Metrics.compactIconCornerRadius

    }

    private var artCenter: CGPoint {

        isExpanded

            ? CGPoint(

                x:

                    24 + 65 / 2,

                y:

                    24 + 65 / 2

            )

            : CGPoint(

                x:

                    Metrics.compactEdgePadding

                    + Metrics.compactIconSize / 2,

                y:

                    DesignTokens

                        .MusicMetrics

                        .compactContentCenterY

            )

    }

    private var waveformSize: CGSize {

        isExpanded

            ? CGSize(

                width:

                    25.57,

                height:

                    24

            )

            : CGSize(

                width:

                    Metrics.compactIconSize,

                height:

                    Metrics.compactIconSize

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

                    DesignTokens

                        .MusicMetrics

                        .compactContentCenterY

            )

    }

    // MARK: - Expanded Layout

    private let titleOrigin =

        CGPoint(

            x: 106,

            y: 36

        )

    private var titleWidth: CGFloat {

        338.85

        - titleOrigin.x

        - 16

    }

    private let progressOrigin =

        CGPoint(

            x: 71,

            y: 112

        )

    private let progressSize =

        CGSize(

            width: 242,

            height: 7

        )

    private let elapsedOrigin =

        CGPoint(

            x: 24,

            y: 106

        )

    private let remainingOrigin =

        CGPoint(

            x: 333,

            y: 106

        )

    private let rowCenterY:

        CGFloat = 159.9

    private let playbackButtonSpacing:

        CGFloat = 70

    private var pauseCenter: CGPoint {

        CGPoint(

            x:

                expandedSize.width / 2,

            y:

                rowCenterY

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

    private let airplayCenter =

        CGPoint(

            x: 335.5,

            y: 159.9

        )

    // MARK: - Body

    var body: some View {

        ZStack(

            alignment:

                .topLeading

        ) {

            // ---------------------------------------------------------

            // Island background

            // ---------------------------------------------------------

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

                DesignTokens

                    .Color

                    .islandBackground

            )

            // ---------------------------------------------------------

            // Album

            // ---------------------------------------------------------

            albumArtView

                .position(

                    artCenter

                )

            // ---------------------------------------------------------

            // Waveform

            //

            // IMPORTANT:

            // Keep this using `artworkColor`.

            //

            // This means the waveform immediately follows the

            // currently reported artwork colour.

            // ---------------------------------------------------------

            Waveform(
                isPlaying: uiIsPlaying,
                color: artworkColor
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

            // ---------------------------------------------------------

            // Expanded content

            // ---------------------------------------------------------

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

        }

        .frame(

            width:

                currentSize.width,

            height:

                currentSize.height

        )

        // MARK: Hover Glow Offset

        .onContinuousHover(

            coordinateSpace:

                .local

        ) { phase in

            guard isExpanded else {

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

        // MARK: Artwork Colour

        .task(

            id:

                currentArtworkFingerprint

        ) {

            guard

                let colorArtwork =

                    realArtwork

            else {

                return

            }

            // ---------------------------------------------------------

            // IMPORTANT:

            //

            // This colour belongs to the current MediaRemote artwork.

            //

            // It is intentionally ONLY assigned to `artworkColor`.

            //

            // We do NOT touch `displayedArtworkColor` here.

            //

            // Therefore the waveform can immediately change colour

            // while the currently visible album keeps its own glow.

            // ---------------------------------------------------------

            artworkColor =

                ArtworkColorExtractor

                    .dominantColor(

                        from:

                            colorArtwork,

                        fallback:

                            DesignTokens

                                .Color

                                .musicAccent

                    )

        }

        // MARK: Initial Artwork

        .onAppear {

            // ---------------------------------------------------------

            // FIRST SONG FIX

            //

            // MediaRemote can already contain artwork before SwiftUI

            // starts observing `onChange`.

            //

            // Establish the front immediately.

            // ---------------------------------------------------------

            if displayedArtwork == nil,

               let artwork =

                    realArtwork {

                displayedArtwork =

                    artwork

                lastArtworkFingerprint =

                    artwork.tiffRepresentation

                // -----------------------------------------------------

                // The first visible album owns this glow colour.

                // -----------------------------------------------------

                displayedArtworkColor =

                    ArtworkColorExtractor

                        .dominantColor(

                            from:

                                artwork,

                            fallback:

                                DesignTokens

                                    .Color

                                    .musicAccent

                        )

            }

            // ---------------------------------------------------------

            // Same fix, for playback state.

            //
            // Without this, if music was already playing when the view
            // mounted, `uiIsPlaying` stayed stuck at its `false`
            // default — the icon showed paused, the waveform sat
            // frozen, and the album art rendered at its paused size/
            // opacity, all despite the song actually playing. It only
            // self-corrected once `isPlaying` genuinely changed, or the
            // user tapped play/pause — which is why toggling it once
            // "fixed" everything.
            // ---------------------------------------------------------

            uiIsPlaying =

                activity.playbackState?.isPlaying
                    ?? false

            // ---------------------------------------------------------

            // Same fix again, for track identity.

            //
            // Without this, `lastTrackKey` stayed `""` past the first
            // song, so the very next real track change — including the
            // first forward/back tap — hit the "this must be the very
            // first track" branch in the track-change handler below
            // instead of the normal one. That branch sets the new
            // artwork directly with no flip, and never arms
            // `pendingTrackKey`, so the flip animation never had a
            // chance to start.
            // ---------------------------------------------------------

            if lastTrackKey.isEmpty,
               !trackKey.isEmpty {

                lastTrackKey =

                    trackKey

            }

        }

        // MARK: Playback State

        .onChange(
            of:
                activity.playbackState?.isPlaying
        ) { _, newValue in

            // External changes (media keys, the source app itself, etc.)
            // should animate the same way a tap on our own button does.
            withAnimation(.easeOut(duration: 0.13)) {
                uiIsPlaying = newValue ?? false
            }
        }

        // MARK: Artwork Arrival

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

            // Same artwork.

            if

                lastArtworkFingerprint

                == newFingerprint

            {

                return

            }

            // ---------------------------------------------------------

            // FIRST REAL ARTWORK

            // ---------------------------------------------------------

            if displayedArtwork == nil {

                displayedArtwork =

                    newArtwork

                incomingArtwork =

                    nil

                lastArtworkFingerprint =

                    newFingerprint

                // First visible artwork gets its colour immediately.

                displayedArtworkColor =

                    ArtworkColorExtractor

                        .dominantColor(

                            from:

                                newArtwork,

                            fallback:

                                DesignTokens

                                    .Color

                                    .musicAccent

                        )

                return

            }

            // ---------------------------------------------------------

            // A NEW TRACK IS WAITING

            // ---------------------------------------------------------

            if

                let pendingTrackKey,

                pendingTrackKey ==

                    trackKey,

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

                lastArtworkFingerprint =

                    newFingerprint

                // -----------------------------------------------------

                // Only now does the visible album's glow change.

                // -----------------------------------------------------

                displayedArtworkColor =

                    ArtworkColorExtractor

                        .dominantColor(

                            from:

                                newArtwork,

                            fallback:

                                DesignTokens

                                    .Color

                                    .musicAccent

                        )

            }

        }

        // MARK: Track Change

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

            // FIRST TRACK

            // ---------------------------------------------------------

            if lastTrackKey.isEmpty {

                lastTrackKey =

                    newKey

                pendingTrackKey =

                    nil

                if let artwork =

                    realArtwork {

                    displayedArtwork =

                        artwork

                    lastArtworkFingerprint =

                        artwork

                            .tiffRepresentation

                    displayedArtworkColor =

                        ArtworkColorExtractor

                            .dominantColor(

                                from:

                                    artwork,

                                fallback:

                                    DesignTokens

                                        .Color

                                        .musicAccent

                            )

                }

                return

            }

            // ---------------------------------------------------------

            // SAME TRACK

            // ---------------------------------------------------------

            guard

                newKey != lastTrackKey

            else {

                return

            }

            lastTrackKey =

                newKey

            // ---------------------------------------------------------

            // Metadata can arrive before artwork.

            //

            // Wait for real artwork before flipping.

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

                        isExpanded
                        && uiIsPlaying,

                    // IMPORTANT:

                    // The FRONT keeps the OLD album's colour

                    // throughout the flip.

                    glowColor:

                        displayedArtworkColor,

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

                        isExpanded
                        && uiIsPlaying,

                    // IMPORTANT:

                    // The back uses the NEW album's extracted colour.

                    //

                    // Since the back is invisible until ~90 degrees,

                    // this colour cannot flash on the old front album.

                    glowColor:

                        incomingArtworkColor,

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

            } else {

                // =====================================================

                // NORMAL

                // =====================================================

                AlbumArtView(

                    image:

                        normalArtwork,

                    size:

                        artSize,

                    cornerRadius:

                        artCornerRadius,

                    showGlow:

                        isExpanded
                        && uiIsPlaying,

                    glowColor:

                        displayedArtworkColor,

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

        .frame(

            width:

                artSize,

            height:

                artSize

        )
        // Paused-state fade — one place, covers the flip transition and
        // the normal (non-flipping) state alike. Size/glow are handled
        // per-instance above since those feed into `AlbumArtView`'s own
        // init params, but opacity is simplest applied once, here, on
        // the outer container all three cases share.
        .opacity(artOpacity)

    }

    // MARK: - Incoming Artwork Colour

    /// Extracts the colour from the artwork that is ABOUT TO become

    /// the front face.

    ///

    /// This is deliberately NOT stored in `displayedArtworkColor`

    /// until the flip has completed.

    private var incomingArtworkColor: Color {

        guard

            let incomingArtwork

        else {

            return displayedArtworkColor

        }

        return ArtworkColorExtractor

            .dominantColor(

                from:

                    incomingArtwork,

                fallback:

                    DesignTokens

                        .Color

                        .musicAccent

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

        // Don't interrupt another flip.

        guard

            !isFlippingAlbum

        else {

            return

        }

        // -------------------------------------------------------------

        // If there is no current album yet, establish it directly.

        // -------------------------------------------------------------

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

            // First visible album gets its colour.

            displayedArtworkColor =

                ArtworkColorExtractor

                    .dominantColor(

                        from:

                            newArtwork,

                        fallback:

                            DesignTokens

                                .Color

                                .musicAccent

                    )

            return

        }

        // -------------------------------------------------------------

        // REAL NEW ARTWORK GOES ON THE BACK

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

        // Physical card rotation

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

            // ---------------------------------------------------------

            // The back is now the front.

            // ---------------------------------------------------------

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

            // ---------------------------------------------------------

            // IMPORTANT:

            //

            // Only NOW does the new album's colour become the

            // displayed album's glow colour.

            //

            // This prevents the yellow/other-colour flash.

            // ---------------------------------------------------------

            self.displayedArtworkColor =

                ArtworkColorExtractor

                    .dominantColor(

                        from:

                            newArtwork,

                        fallback:

                            DesignTokens

                                .Color

                                .musicAccent

                    )

        }

    }

    // MARK: - Track Navigation

    private func skipForwardWithFlip() {

        pendingFlipDirection =

            1

        forwardSkipTrigger += 1

        activity.skipForward()

    }

    private func skipBackwardWithFlip() {

        pendingFlipDirection =

            -1

        backwardSkipTrigger += 1

        activity.skipBackward()

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

                titleWidth,

            alignment:

                .leading

        )

        .offset(

            x:

                titleOrigin.x,

            y:

                titleOrigin.y

        )

        .fadeOnly(

            isVisible:

                isExpanded,

            delay:

                isExpanded

                ? 0.08

                : 0,

            duration:

                0.25

        )

        .allowsHitTesting(

            isExpanded

        )

    }

    // MARK: - Progress Bar

    private var progressBar: some View {

        GeometryReader { proxy in

            ZStack(

                alignment:

                    .leading

            ) {

                // ---------------------------------------------------------

                // Background

                // ---------------------------------------------------------

                Capsule()

                    .fill(

                        Color.white.opacity(

                            0.2

                        )

                    )

                // ---------------------------------------------------------

                // Progress

                // ---------------------------------------------------------

                Capsule()

                    .fill(

                        DesignTokens

                            .Color

                            .primaryText

                    )

                    .frame(

                        width:

                            proxy.size.width

                            * progressFraction

                    )

            }

            // -------------------------------------------------------------

            // Invisible enlarged hit area.

            //

            // The visual bar stays 7pt.

            // User gets a much easier area to grab.

            // -------------------------------------------------------------

            .contentShape(

                Rectangle()

                    .inset(

                        by:

                            -8

                    )

            )

            // -------------------------------------------------------------

            // CLICK + DRAG TO SEEK

            // -------------------------------------------------------------

            .gesture(

                DragGesture(

                    minimumDistance:

                        0,

                    coordinateSpace:

                        .local

                )

                .onChanged { value in

                    guard

                        isExpanded

                    else {

                        return

                    }

                    let width =

                        max(

                            proxy.size.width,

                            1

                        )

                    let fraction =

                        min(

                            max(

                                value.location.x

                                / width,

                                0

                            ),

                            1

                        )

                    let duration =

                        activity

                            .playbackState?

                            .duration

                        ?? 0

                    guard

                        duration > 0

                    else {

                        return

                    }

                    // -----------------------------------------------------

                    // Start scrubbing.

                    // -----------------------------------------------------

                    if !isSeeking {

                        isSeeking =

                            true

                    }

                    // -----------------------------------------------------

                    // IMPORTANT:

                    //

                    // Do NOT send MediaRemote on every mouse movement.

                    //

                    // We only visually update the preview here.

                    // -----------------------------------------------------

                    seekPreviewElapsed =

                        duration

                        * fraction

                }

                .onEnded { value in

                    guard

                        isExpanded

                    else {

                        return

                    }

                    let width =

                        max(

                            proxy.size.width,

                            1

                        )

                    let fraction =

                        min(

                            max(

                                value.location.x

                                / width,

                                0

                            ),

                            1

                        )

                    let duration =

                        activity

                            .playbackState?

                            .duration

                        ?? 0

                    guard

                        duration > 0

                    else {

                        isSeeking =

                            false

                        return

                    }

                    let target =

                        duration

                        * fraction

                    // -----------------------------------------------------

                    // Keep the visual position at the final target.

                    // -----------------------------------------------------

                    seekPreviewElapsed =

                        target

                    // -----------------------------------------------------

                    // ACTUAL SEEK

                    // -----------------------------------------------------

                    activity.seek(

                        to:

                            target

                    )

                    // Keep the preview active until MediaRemote has had

                    // a chance to report the new position.

                    //

                    // This prevents the old position from flashing back

                    // onto the UI immediately after the click.

                    DispatchQueue.main.asyncAfter(

                        deadline:

                            .now() + 0.35

                    ) {

                        isSeeking = false

                    }

                }

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

        )

        .fadeOnly(

            isVisible:

                isExpanded,

            delay:

                isExpanded

                ? 0.10

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

            DesignTokens

                .Color

                .secondaryText

        )

        .offset(

            x:

                elapsedOrigin.x,

            y:

                elapsedOrigin.y

        )

        .fadeOnly(

            isVisible:

                isExpanded,

            delay:

                isExpanded

                ? 0.10

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

            DesignTokens

                .Color

                .secondaryText

        )

        .offset(

            x:

                remainingOrigin.x,

            y:

                remainingOrigin.y

        )

        .fadeOnly(

            isVisible:

                isExpanded,

            delay:

                isExpanded

                ? 0.10

                : 0,

            duration:

                0.25

        )

    }

    // MARK: - Previous Button

    private var previousButton: some View {

        Button(
            action:
                skipBackwardWithFlip
        ) {

            SkipChevronsIcon(
                forward: false,
                trigger: backwardSkipTrigger
            )
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())

        .opacity(

            0.7

        )

        .position(

            x:

                previousCenter.x,

            y:

                previousCenter.y

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

    // MARK: - Pause / Play

    private var pauseButton: some View {

        PlaybackButton(

            systemName:

                uiIsPlaying
                ? "pause.fill"
                : "play.fill",

            action:
                togglePlayPauseWithUI,

            size:

                36

        )

        .frame(

            width:

                38,

            height:

                38

        )

        .position(

            x:

                pauseCenter.x,

            y:

                pauseCenter.y

        )

        .fadeOnly(

            isVisible:

                isExpanded,

            delay:

                isExpanded

                ? 0.14

                : 0,

            duration:

                0.14

        )

        .allowsHitTesting(

            isExpanded

        )

    }

    private func togglePlayPauseWithUI() {

        withAnimation(AnimationTokens.stateUpdate) {
            uiIsPlaying.toggle()
        }

        activity.togglePlayPause()
    }
    // MARK: - Next Button

    private var nextButton: some View {

        Button(
            action:
                skipForwardWithFlip
        ) {

            SkipChevronsIcon(
                forward: true,
                trigger: forwardSkipTrigger
            )
            .foregroundStyle(.white)
            .frame(width: 50, height: 50)
        }
        .buttonStyle(.plain)
        .contentShape(Circle())

        .opacity(

            0.7

        )

        .position(

            x:

                nextCenter.x,

            y:

                nextCenter.y

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

    // MARK: - AirPlay

    private var airplayButton: some View {

        Image(systemName: "airplayaudio")
            .font(.system(size: 18))
            .foregroundStyle(
                DesignTokens.Color.primaryText
            )
            .frame(
                width: Metrics.airplayIconSize,
                height: Metrics.airplayIconSize
            )
            .contentShape(Rectangle())
            .position(
                x: airplayCenter.x,
                y: airplayCenter.y
            )
            .fadeOnly(
                isVisible: isExpanded,
                delay: isExpanded ? 0.14 : 0,
                duration: 0.25
            )
            .allowsHitTesting(isExpanded)
            .onTapGesture {
                guard isExpanded else { return }

                outputDeviceManager.refresh()

                OutputDevicePanelController.shared.toggle(
                    manager: outputDeviceManager
                )
            }
    }

    // MARK: - Derived Values

    private var displayedElapsed: TimeInterval {

        if isSeeking {

            return seekPreviewElapsed

        }

        return activity

            .playbackState?

            .elapsed

            ?? 0

    }

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

        let duration =

            activity

                .playbackState?

                .duration

            ?? 0

        guard duration > 0 else {

            return 0

        }

        return min(

            max(

                displayedElapsed / duration,

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

// MARK: - Fade Only

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
