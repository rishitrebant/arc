import SwiftUI
import AppKit
import CoreImage

/// Extracts a single dominant color from artwork — weighted toward
/// bright, saturated pixels, ignoring dark/neutral ones, sampled on a
/// small downscaled copy for speed.
///
/// Moved out of `AlbumArtView` (where this was originally written and
/// worked correctly for the album art's own glow) into a shared location
/// so `MusicIslandView` can compute it ONCE and hand the same `Color` to
/// both the glow AND the waveform — rather than each duplicating the
/// algorithm independently, which risks them drifting to slightly
/// different colors over time as either copy gets tweaked separately.
/// The algorithm itself is untouched: same 24×24 sample size, same
/// brightness/saturation thresholds, same weighting curve.
enum ArtworkColorExtractor {
    static func dominantColor(from image: NSImage?, fallback: Color) -> Color {
        guard
            let image,
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else {
            return fallback
        }

        let width = 24
        let height = 24

        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }

        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

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
            let saturation = maxValue > 0 ? (maxValue - minValue) / maxValue : 0

            // Ignore dark / neutral parts of the artwork.
            guard brightness > 0.20, saturation > 0.15 else { continue }

            // Strongly favour bright, saturated colours.
            let weight = pow(saturation, 3.0) * pow(brightness, 2.0)

            red += r * weight
            green += g * weight
            blue += b * weight
            totalWeight += weight
        }

        guard totalWeight > 0 else { return fallback }

        return Color(red: red / totalWeight, green: green / totalWeight, blue: blue / totalWeight)
    }
}
