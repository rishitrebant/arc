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
struct YouTubeIslandView: View {

    @ObservedObject var activity: YouTubeActivity
    let isExpanded: Bool

    @StateObject private var outputDeviceManager = AudioOutputDeviceManager()

    private typealias Metrics = DesignTokens.MusicMetrics

    private var video: WebVideoState? { activity.video }

    private var compactSize: CGSize { activity.compactSize }

    private var expandedSize: CGSize { activity.expandedSize }

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
            .frame(width: 96, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .position(x: 24 + 48, y: 40 + 27)

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
            .frame(width: 198, alignment: .leading)
            .position(x: 132 + 99, y: 40 + 27)

            // Waveform, top right — as in Music.
            LiveWaveform(
                isPlaying: video?.isPlaying ?? false,
                color: DesignTokens.Color.youtubeRed
            )
            .frame(width: 25.57, height: 24)
            .position(x: 338.85 + 25.57 / 2, y: 40 + 12)

            // Progress.
            ProgressBar(
                elapsed: video?.elapsed ?? 0,
                duration: video?.duration ?? 0
            )
            .position(x: expandedSize.width / 2, y: 118)

            // Transport: back 5s · play/pause · forward 5s.
            PlaybackButton(
                systemName: "gobackward.5",
                action: { activity.skipBack() },
                size: 24,
                buttonSize: 44
            )
            .position(x: expandedSize.width / 2 - Metrics.playbackButtonSpacingExpanded, y: 164)
            .accessibilityLabel("Back 5 seconds")

            PlaybackButton(
                systemName: (video?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                action: { activity.togglePlayPause() },
                size: 32,
                buttonSize: 50
            )
            .position(x: expandedSize.width / 2, y: 164)
            .accessibilityLabel((video?.isPlaying ?? false) ? "Pause" : "Play")

            PlaybackButton(
                systemName: "goforward.5",
                action: { activity.skipForward() },
                size: 24,
                buttonSize: 44
            )
            .position(x: expandedSize.width / 2 + Metrics.playbackButtonSpacingExpanded, y: 164)
            .accessibilityLabel("Forward 5 seconds")

            // Output picker, bottom right — as in Music.
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Metrics.airplayIconSize, height: Metrics.airplayIconSize)
                .contentShape(Rectangle())
                .position(x: 335.5, y: 164)
                .onTapGesture {
                    outputDeviceManager.refresh()
                    OutputDevicePanelController.shared.toggle(manager: outputDeviceManager)
                }
        }
    }
}
