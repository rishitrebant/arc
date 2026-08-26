import SwiftUI
import AppKit
import CoreImage

struct AlbumArtView: View {

    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat
    var accent: Color = DesignTokens.Color.musicAccent

    @State private var artworkColor: Color = .clear

    var body: some View {

        ZStack {

            // MARK: - Dynamic album-art glow

            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .fill(artworkColor.opacity(0.32))
            .frame(
                width: size + 18,
                height: size + 18
            )
            .blur(radius: 14)

            // MARK: - Album artwork

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
                    .font(
                        .system(
                            size: size * 0.32,
                            weight: .semibold
                        )
                    )
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
        .task(id: image?.tiffRepresentation) {
            artworkColor = extractArtworkColor(from: image)
        }
    }

    // MARK: - Artwork colour extraction

    private func extractArtworkColor(from image: NSImage?) -> Color {

        guard
            let image,
            let cgImage = image.cgImage(
                forProposedRect: nil,
                context: nil,
                hints: nil
            )
        else {
            return accent
        }

        let ciImage = CIImage(cgImage: cgImage)

        let filter = CIFilter(name: "CIAreaAverage")

        filter?.setValue(ciImage, forKey: kCIInputImageKey)

        filter?.setValue(
            CIVector(
                x: ciImage.extent.origin.x,
                y: ciImage.extent.origin.y,
                z: ciImage.extent.size.width,
                w: ciImage.extent.size.height
            ),
            forKey: kCIInputExtentKey
        )

        guard
            let outputImage = filter?.outputImage,
            let cgAverage = CIContext().createCGImage(
                outputImage,
                from: CGRect(x: 0, y: 0, width: 1, height: 1)
            ),
            let dataProvider = cgAverage.dataProvider,
            let data = dataProvider.data,
            let bytes = CFDataGetBytePtr(data)
        else {
            return accent
        }

        let red = CGFloat(bytes[0]) / 255
        let green = CGFloat(bytes[1]) / 255
        let blue = CGFloat(bytes[2]) / 255

        return Color(
            red: red,
            green: green,
            blue: blue
        )
    }
}
