import SwiftUI

struct PlaybackButton: View {

    let systemName: String
    let action: () -> Void

    var size: CGFloat = 20
    var buttonSize: CGFloat = 34

    var body: some View {

        Button(action: action) {

            Image(systemName: systemName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: buttonSize, height: buttonSize)
                // Apple's built-in "replace" symbol effect: the old
                // glyph shrinks toward zero and fades out, the new one
                // grows from zero and fades in — rather than the old
                // plain cross-fade this used to do via the
                // `.animation(value: systemName)` below. Used for the
                // play/pause icon; actually animates whenever the
                // change happens inside a `withAnimation` block (see
                // `MusicIslandView.togglePlayPauseWithUI`).
                .contentTransition(.symbolEffect(.replace))

        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .scaleEffect(1.0)

    }
}
