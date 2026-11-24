import SwiftUI

/// The YouTube logo mark: a red rounded rectangle with a white play
/// triangle, drawn in code (no image asset).
struct YouTubeLogoMark: View {

    var height: CGFloat

    private struct PlayTriangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    var body: some View {

        RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
            .fill(DesignTokens.Color.youtubeRed)
            .frame(width: height * 1.42, height: height)
            .overlay {
                PlayTriangle()
                    .fill(Color.white)
                    .frame(width: height * 0.34, height: height * 0.4)
                    .offset(x: height * 0.03)
            }
    }
}

/// What the compact pill shows on its left — the YouTube logo or the
/// video's thumbnail, per Settings. Falls back to the logo while there's
/// no thumbnail yet.
struct YouTubeCompactIconView: View {

    let video: WebVideoState?
    let size: CGFloat

    var body: some View {

        if AppSettings.youtubeCompactIcon == .thumbnail,
           let thumbnail = video?.thumbnail {

            Image(nsImage: thumbnail)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: DesignTokens.MusicMetrics.compactIconCornerRadius,
                        style: .continuous
                    )
                )

        } else {

            YouTubeLogoMark(height: size * 0.72)
                .frame(width: size, height: size)
        }
    }
}

/// Renders `YouTubeActivity` with the same template as Music:
///   - compact: logo / thumbnail on the left, waveform on the right
///   - expanded: thumbnail, title, channel, progress, and the controls —
///     back 5 s, play / pause, forward 5 s — plus the output picker.
///
/// A LIVE stream has no timeline: the progress bar and the forward button
/// are dropped, "back" becomes a 15-second rewind, a small LIVE tag sits
/// beside the channel name, and the transport row moves up.
struct YouTubeIslandView: View {

    @ObservedObject var activity: YouTubeActivity
    let isExpanded: Bool

    @StateObject private var outputDeviceManager = AudioOutputDeviceManager()

    private typealias Metrics = DesignTokens.MusicMetrics

    private var video: WebVideoState? { activity.video }

    private var isLive: Bool { video?.isLive == true }

    private var compactSize: CGSize { activity.compactSize }

    private var expandedSize: CGSize { activity.expandedSize }

    // Geometry. A recorded video has a progress bar between the header and
    // the transport row. A live stream doesn't, so its header grows (a
    // bigger thumbnail) and the two blocks are centred in the card —
    // otherwise there's a dead band where the bar would be.

    private var thumbnailSize: CGSize {
        isLive ? CGSize(width: 112, height: 63) : CGSize(width: 96, height: 54)
    }

    private var headerCenterY: CGFloat { isLive ? 84 : 67 }

    private var transportY: CGFloat { isLive ? 156 : 164 }

    private var titleX: CGFloat {
        24 + thumbnailSize.width + 14
    }

    private var titleWidth: CGFloat {
        // Up to the top-right slot (waveform, or LIVE on a live stream).
        (isLive ? 326 : 330) - titleX
    }

    var body: some View {

        IslandMorphSurface(
            isExpanded: isExpanded,
            compactSize: compactSize,
            expandedSize: expandedSize
        ) {
            compactRow
        } expanded: {
            expandedPanel
        }
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(alignment: .center) {

            YouTubeCompactIconView(video: video, size: Metrics.compactIconSize)

            Spacer(minLength: 0)

            LiveWaveform(
                isPlaying: video?.isPlaying ?? false,
                color: DesignTokens.Color.youtubeRed
            )
            .frame(width: Metrics.compactIconSize, height: Metrics.compactIconSize)
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }

    // MARK: - Expanded
    //
    // Laid out on the same grid as Music's expanded card: 390 × 200,
    // thumbnail at the left, waveform at the top right, the progress bar
    // under them, the transport row at the bottom.

    /// The red "LIVE" tag — in the top-right slot, where the waveform sits
    /// on a recorded video.
    private var liveTag: some View {

        HStack(spacing: 5) {

            Circle()
                .fill(DesignTokens.Color.youtubeRed)
                .frame(width: 7, height: 7)

            Text("LIVE")
                .font(.system(size: 11, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(DesignTokens.Color.primaryText)
        }
        .padding(.horizontal, 9)
        .frame(height: 22)
        .background(
            Capsule().fill(DesignTokens.Color.youtubeRed.opacity(0.3))
        )
    }

    private var expandedPanel: some View {

        ZStack(alignment: .topLeading) {

            // Thumbnail (16:9) — sits below the notch cut-out.
            Group {
                if let thumbnail = video?.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(DesignTokens.Color.deviceIconBackground)
                        .overlay { YouTubeLogoMark(height: 20) }
                }
            }
            .frame(width: thumbnailSize.width, height: thumbnailSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .position(
                x: 24 + thumbnailSize.width / 2,
                y: headerCenterY
            )

            // Title and channel.
            VStack(alignment: .leading, spacing: 3) {

                Text(video?.title ?? "")
                    .font(DesignTokens.Typography.title)
                    .tracking(DesignTokens.Typography.letterSpacingTight)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(video?.channel ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: titleWidth, alignment: .leading)
            .position(x: titleX + titleWidth / 2, y: headerCenterY)

            // Top right: the waveform — or, on a live stream, LIVE.
            Group {
                if isLive {
                    liveTag
                } else {
                    LiveWaveform(
                        isPlaying: video?.isPlaying ?? false,
                        color: DesignTokens.Color.youtubeRed
                    )
                    .frame(width: 25.57, height: 24)
                }
            }
            .position(
                x: isLive ? expandedSize.width - 24 - 28 : 338.85 + 25.57 / 2,
                y: isLive ? headerCenterY - thumbnailSize.height / 2 + 11 : 40 + 12
            )

            // Progress. A live stream has no timeline to show.
            if !isLive {
                ProgressBar(
                    elapsed: video?.elapsed ?? 0,
                    duration: video?.duration ?? 0
                )
                .position(x: expandedSize.width / 2, y: 118)
            }

            // Transport. On a live stream "back" is 15 s (a relative
            // rewind — there's no position to seek from) and there is no
            // forward.
            PlaybackButton(
                systemName: isLive ? "gobackward.15" : "gobackward.5",
                action: { activity.skipBack() },
                size: 24,
                buttonSize: 44
            )
            .position(
                x: expandedSize.width / 2 - Metrics.playbackButtonSpacingExpanded,
                y: transportY
            )
            .accessibilityLabel(isLive ? "Back 15 seconds" : "Back 5 seconds")

            PlaybackButton(
                systemName: (video?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                action: { activity.togglePlayPause() },
                size: 32,
                buttonSize: 50
            )
            .position(x: expandedSize.width / 2, y: transportY)
            .accessibilityLabel((video?.isPlaying ?? false) ? "Pause" : "Play")

            if !isLive {
                PlaybackButton(
                    systemName: "goforward.5",
                    action: { activity.skipForward() },
                    size: 24,
                    buttonSize: 44
                )
                .position(
                    x: expandedSize.width / 2 + Metrics.playbackButtonSpacingExpanded,
                    y: transportY
                )
                .accessibilityLabel("Forward 5 seconds")
            }

            // Output picker, bottom right — as in Music.
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Metrics.airplayIconSize, height: Metrics.airplayIconSize)
                .contentShape(Rectangle())
                .position(x: 335.5, y: transportY)
                .onTapGesture {
                    outputDeviceManager.refresh()
                    OutputDevicePanelController.shared.toggle(manager: outputDeviceManager)
                }
        }
    }
}
