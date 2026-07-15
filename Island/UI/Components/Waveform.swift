import SwiftUI

/// The small animated waveform shown in the music pill (compact and
/// expanded). Matches the yellow bars visible in `ongoing music.png`.
struct Waveform: View {
    var isPlaying: Bool
    var color: Color = DesignTokens.Color.musicAccent
    var barCount: Int = 4

    @State private var pulse = false

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: barHeight(for: index))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 16)
        .onAppear { setPulsing(isPlaying) }
        .onChange(of: isPlaying) { newValue in setPulsing(newValue) }
    }

    /// Explicitly wraps the state change in its own `withAnimation` rather
    /// than relying on an ambient `.animation(value:)` modifier. This view
    /// gets inserted mid-transition (during the hover expand/collapse,
    /// which already has its own explicit `withAnimation` around it) — an
    /// ambient ".animation" modifier here would get swallowed by that
    /// enclosing explicit transaction and never actually start the
    /// repeating pulse, which is exactly what was happening before (bars
    /// rendered flat, like static dots, instead of animating). Wrapping the
    /// mutation in its own explicit `withAnimation` guarantees this
    /// specific animation wins regardless of what's happening around it.
    private func setPulsing(_ playing: Bool) {
        if playing {
            withAnimation(.easeInOut(duration: 0.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulse = false
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        guard pulse else { return 6 }
        // Slightly offset heights per bar so they don't move in lockstep,
        // reading as a natural waveform rather than a synced blink.
        let base: [CGFloat] = [8, 16, 11, 14]
        return base[index % base.count]
    }
}
