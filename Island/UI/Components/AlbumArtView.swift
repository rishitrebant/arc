import SwiftUI
import AppKit
import CoreImage

struct AlbumArtView: View {
    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat
    var accent: Color = DesignTokens.Color.musicAccent
    var showGlow: Bool = false
    
    @State private var artworkColor: Color = .clear
    
    var body: some View {
        ZStack {

            // MARK: - Subtle artwork glow
            if showGlow {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(artworkColor.opacity(0.26))
                .frame(
                    width: size + 8,
                    height: size + 8
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
                x: 0,
                y: 2
            )
        }
        // Extra room so the glow can actually exist outside the album.
        .frame(
            width: size + 12,
            height: size + 12
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
        
        let width = 24
        let height = 24
        
        var pixels = [UInt8](
            repeating: 0,
            count: width * height * 4
        )
        
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return accent
        }
        
        context.interpolationQuality = .medium
        context.draw(
            cgImage,
            in: CGRect(x: 0, y: 0, width: width, height: height)
        )
        
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var totalWeight: CGFloat = 0
        
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let r = CGFloat(pixels[i]) / 255
            let g = CGFloat(pixels[i + 1]) / 255
            let b = CGFloat(pixels[i + 2]) / 255
            let a = CGFloat(pixels[i + 3]) / 255
            
            guard a > 0.2 else { continue }
            
            let maxValue = max(r, g, b)
            let minValue = min(r, g, b)
            let brightness = maxValue
            let saturation = maxValue > 0
            ? (maxValue - minValue) / maxValue
            : 0
            
            // Ignore dark / neutral parts of the artwork.
            guard brightness > 0.20, saturation > 0.15 else {
                continue
            }
            
            // Strongly favour bright, saturated colours.
            let weight =
            pow(saturation, 3.0) *
            pow(brightness, 2.0)
            
            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }
        
        guard totalWeight > 0 else {
            return accent
        }
        
        let r = red / totalWeight
        let g = green / totalWeight
        let b = blue / totalWeight
        
        return Color(
            red: r,
            green: g,
            blue: b
        )
    }
}
