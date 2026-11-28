import SwiftUI

/// A system-volume slider in the style of Apple's Now Playing control:
/// a small speaker, a thin bar you can drag, a larger speaker.
struct SystemVolumeBar: View {

    @ObservedObject var volume: SystemVolumeControl

    var width: CGFloat = 160

    var body: some View {

        HStack(spacing: 9) {

            Image(systemName: "speaker.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)

            ZStack(alignment: .leading) {

                Capsule().fill(Color.white.opacity(0.2))

                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(4, width * volume.level))
            }
            .frame(width: width, height: 4)
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        volume.set(value.location.x / width)
                    }
            )

            Image(systemName: "speaker.wave.3.fill")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)
        }
        .animation(.easeOut(duration: 0.1), value: volume.level)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Volume")
        .accessibilityValue("\(Int(volume.level * 100)) percent")
    }
}
