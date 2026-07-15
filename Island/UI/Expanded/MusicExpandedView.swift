import SwiftUI

/// The expanded, hover-triggered presentation of Music — matches
/// `Figma exports/Measurements/Music Expanded.png` layout and spacing,
/// refined for Apple-level polish: more breathing room, a clearer type
/// hierarchy, a play/pause button that reads as the visual anchor, and a
/// sequenced entrance/exit for everything that isn't a shared element with
/// the compact state.
struct MusicExpandedView: View {
    @ObservedObject var activity: MusicActivity

    @Environment(\.islandNamespace) private var namespace

    private var metrics: DesignTokens.MusicMetrics.Type { DesignTokens.MusicMetrics.self }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, DesignTokens.Spacing.xs) // tight — progress bar sits high, close to the title

            ProgressBar(
                elapsed: activity.playbackState?.elapsed ?? 0,
                duration: activity.playbackState?.duration ?? 0,
                width: metrics.progressBarWidth
            )
            .transition(AnimationTokens.contentTransition(insertDelay: 0.05, removeDelay: 0.02))
            .padding(.bottom, DesignTokens.Spacing.sm) // controls get breathing room, kept in budget

            controls
                .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
        }
        .padding(.top, metrics.expandedTopPadding)
        .padding([.horizontal, .bottom], metrics.expandedEdgePadding)
        .frame(width: metrics.expandedWidth, height: metrics.expandedHeight, alignment: .top)
        .background(
            IslandShape.body(bottomRadius: DesignTokens.Shape.expandedBottomRadius)
                .fill(DesignTokens.Color.islandBackground)
                .islandMatchedGeometry(id: "islandBody", namespace: namespace)
        )
    }

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            AlbumArtView(
                image: activity.playbackState?.artwork,
                size: metrics.albumArtSize,
                cornerRadius: metrics.albumArtCornerRadius
            )
            .islandMatchedGeometry(id: "albumArt", namespace: namespace)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(activity.playbackState?.title ?? "")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)

                Text(activity.playbackState?.artist ?? "")
                    .font(DesignTokens.Typography.subtitle)
                    .tracking(DesignTokens.Typography.letterSpacingTight)
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .lineLimit(1)
            }
            .transition(AnimationTokens.contentTransition(insertDelay: 0.02, removeDelay: 0.04))

            Spacer(minLength: 0)

            Waveform(isPlaying: activity.playbackState?.isPlaying ?? false)
                .frame(width: metrics.waveformIconWidth)
                .islandMatchedGeometry(id: "waveform", namespace: namespace)
        }
    }

    private var controls: some View {
        HStack {
            Spacer(minLength: 0)

            HStack(spacing: metrics.playbackButtonSpacing) {
                // Secondary — smaller and slightly dimmer so play/pause reads
                // as the anchor of the row, not just another button.
                PlaybackButton(systemName: "backward.fill", action: activity.skipBackward, size: 16)
                    .opacity(0.7)

                PlaybackButton(
                    systemName: (activity.playbackState?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                    action: activity.togglePlayPause,
                    size: 20
                )
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.white.opacity(0.14)))

                PlaybackButton(systemName: "forward.fill", action: activity.skipForward, size: 16)
                    .opacity(0.7)
            }
            // No fixed width here — the original 101.3pt spec assumed much
            // smaller glyphs. Sizing intrinsically and centering via the
            // flanking Spacers keeps it correct regardless of button size.

            Spacer(minLength: 0)

            // AirPlay-style routing icon, matches the rightmost glyph in
            // "Music Hover.png" / "Music Expanded.png".
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: metrics.waveformIconWidth)
        }
    }
}
