import SwiftUI
import AppKit

/// Album artwork with the measured corner radius, falling back to a
/// placeholder tinted with the activity's accent color when no artwork is
/// available yet — reads as an intentional brand mark rather than a
/// generic broken-image box.
struct AlbumArtView: View {
    var image: NSImage?
    var size: CGFloat
    var cornerRadius: CGFloat
    var accent: Color = DesignTokens.Color.musicAccent

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(accent.opacity(0.16))
            .frame(width: size, height: size)
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(accent)
                        .font(.system(size: size * 0.34, weight: .semibold))
                }
            }
    }
}
