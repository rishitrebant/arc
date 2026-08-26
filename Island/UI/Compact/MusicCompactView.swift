import SwiftUI

/// The compact, notch-width presentation of Music — matches
/// `Trials/Ongoing music.png`: small rounded artwork on the left,
/// animated waveform on the right, pure black background flush against
/// the notch on top with rounded bottom corners only.
struct MusicCompactView: View {
    @ObservedObject var activity: MusicActivity

    @Environment(\.islandNamespace) private var namespace

    private var metrics: DesignTokens.MusicMetrics.Type { DesignTokens.MusicMetrics.self }

    var body: some View {
        HStack(alignment: .center) {
            AlbumArtView(
                image: activity.playbackState?.artwork,
                size: metrics.compactIconSize,
                cornerRadius: metrics.compactIconCornerRadius
            )
            .islandMatchedGeometry(id: "albumArt", namespace: namespace)

            Spacer(minLength: 0)

            // Framed to the same width as the artwork — a bare waveform is
            // visually much lighter than the artwork, which pulls the whole
            // pill's perceived center toward the left. Equal-width slots on
            // both ends is what actually makes the pill read as centered.
            Waveform(isPlaying: activity.playbackState?.isPlaying ?? false)
                .frame(width: metrics.compactIconSize, height: metrics.compactIconSize)
                .islandMatchedGeometry(id: "waveform", namespace: namespace)
        }
        .padding(.horizontal, metrics.compactEdgePadding) // was Spacing.sm (16) — dedicated 10pt token now
        .frame(width: metrics.compactWidth, height: metrics.compactHeight)
        .background(
            IslandShape(
                topRadius: DesignTokens.Shape.compactTopRadius,
                bottomRadius: DesignTokens.Shape.compactBottomRadius
            )
                .fill(DesignTokens.Color.islandBackground)
                .islandMatchedGeometry(id: "islandBody", namespace: namespace)
        )
    }
}
