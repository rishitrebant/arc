import SwiftUI
import AppKit

struct AlbumArtView: View {

    var image: NSImage?

    var size: CGFloat

    var cornerRadius: CGFloat

    var accent: Color = DesignTokens.Color.musicAccent

    var body: some View {

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

                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(accent)

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
            y: 2
        )
    }

}
