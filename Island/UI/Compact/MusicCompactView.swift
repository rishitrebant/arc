import SwiftUI

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

            Waveform(isPlaying: activity.playbackState?.isPlaying ?? false)
                .frame(width: metrics.compactIconSize)
                .islandMatchedGeometry(id: "waveform", namespace: namespace)
        }
        .padding(.horizontal, metrics.compactEdgePadding) // was DesignTokens.Spacing.sm (16) — now the dedicated 10pt token above
        .frame(width: metrics.compactWidth, height: metrics.compactHeight)
        .background(
            IslandShape.body(
                topRadius: DesignTokens.Shape.compactTopRadius,
                bottomRadius: DesignTokens.Shape.compactBottomRadius
            )
                .fill(DesignTokens.Color.islandBackground)
                .islandMatchedGeometry(id: "islandBody", namespace: namespace)
        )
    }
}
