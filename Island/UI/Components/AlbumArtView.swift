import SwiftUI
import AppKit

struct AlbumArtView: View {

    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat
    var showGlow: Bool = false

    /// Glow colour supplied by MusicIslandView.
    var glowColor: Color =
        DesignTokens.Color.musicAccent

    /// Mouse-driven offset supplied by MusicIslandView.
    var glowOffset: CGSize = .zero

    var body: some View {
        ZStack {

            // MARK: - Album glow

            if showGlow {

                // Wide, soft outer glow
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(
                    glowColor.opacity(0.18)
                )
                .frame(
                    width: size + 30,
                    height: size + 30
                )
                .blur(radius: 12)
                .offset(glowOffset)

                // Tighter inner glow
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(
                    glowColor.opacity(0.24)
                )
                .frame(
                    width: size + 10,
                    height: size + 10
                )
                .blur(radius: 7)
                .offset(glowOffset)
            }

            // MARK: - Album artwork

            ZStack {

                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(
                    Color.white.opacity(0.06)
                )

                if let image {

                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(
                            contentMode: .fill
                        )

                } else {

                    Image("Currents")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(
                            contentMode: .fill
                        )
                }
            }
            .frame(
                width: size,
                height: size
            )
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

        // Extra room for the outer glow.
        .frame(
            width: size + 24,
            height: size + 24
        )
    }
}
