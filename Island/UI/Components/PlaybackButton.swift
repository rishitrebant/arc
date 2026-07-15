import SwiftUI

/// A single playback control (back / play-pause / forward), matching the
/// icon-only white buttons in "Music Expanded.png".
struct PlaybackButton: View {
    let systemName: String
    let action: () -> Void
    var size: CGFloat = 20

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
