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


/// A thin draggable level bar for any 0…1-ish value (the Pomodoro's sound
/// volume), in the same style as the system volume bar.
struct ThinSlider: View {

    @Binding var value: Double
    let range: ClosedRange<Double>
    var onChange: () -> Void = {}

    var body: some View {

        GeometryReader { proxy in

            let width = max(1, proxy.size.width)
            let span = range.upperBound - range.lowerBound
            let fraction = (value - range.lowerBound) / span

            ZStack(alignment: .leading) {

                Capsule().fill(Color.white.opacity(0.2))

                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: max(4, width * fraction))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let raw = range.lowerBound + span * Double(drag.location.x / width)
                        value = min(max(raw, range.lowerBound), range.upperBound)
                        onChange()
                    }
            )
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.1), value: value)
    }
}

/// A small back button for the corner of an activity's open card: it
/// returns to the launcher menu, whatever was running when you hovered.
struct LauncherBackButton: View {

    var body: some View {

        Button {
            NotificationCenter.default.post(name: .islandOpenLauncher, object: nil)
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: 24, height: 24)
                .background(Circle().fill(DesignTokens.Color.controlDisc))
        }
        .buttonStyle(PressableButtonStyle())
        .padding(.leading, 12)
        .padding(.top, 5)
        .accessibilityLabel("Back to launcher")
    }
}
