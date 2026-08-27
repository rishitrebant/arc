import SwiftUI
import AppKit

struct AlbumArtView: View {
    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat
    var showGlow: Bool = false
    /// The glow's color — now supplied by the caller (see
    /// `MusicIslandView`) instead of computed internally, so the exact
    /// same extracted color can also be handed to the waveform. The
    /// extraction algorithm itself didn't change or move away from being
    /// "this view's color" conceptually — it just now lives in
    /// `ArtworkColorExtractor` so it's not duplicated per-consumer.
    var glowColor: Color = DesignTokens.Color.musicAccent

    var body: some View {
        ZStack {

            // MARK: - Subtle artwork glow
            if showGlow {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(glowColor.opacity(0.50))
                .frame(
                    width: size + 12,
                    height: size + 12
                )
                .blur(radius: 9)
            }
            // MARK: - Album artwork
            ZStack {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.06))

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image("Currents")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fill)
                }
            }
            .frame(width: size, height: size)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .shadow(
                color: .black.opacity(0.22),
                radius: 6,
                x: 0,
                y: 2
            )
        }
        // Extra room so the glow can actually exist outside the album.
        .frame(
            width: size + 12,
            height: size + 12
        )
    }
}
