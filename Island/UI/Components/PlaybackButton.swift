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

        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .scaleEffect(1.0)
        .animation(.easeOut(duration: 0.15), value: systemName)

    }
}
