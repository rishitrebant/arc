import SwiftUI

/// The small animated waveform shown in the music pill (compact and
/// expanded). Six thin bars, 1.83pt apart — matches Apple's own equalizer
/// glyph proportions rather than the previous 4 thick bars.
///
/// Bar width is computed from whatever width the caller constrains this
/// view to (via `.frame(width:)` at the call site), not hardcoded — the
/// same component is used at two different sizes (22pt in the compact
/// pill, 25.57pt in the expanded view) and both need to read as "the same
/// waveform, scaled," not two different-looking waveforms that happen to
/// share code.
struct Waveform: View {
    var isPlaying: Bool
    var color: Color = DesignTokens.Color.musicAccent
    var barCount: Int = DesignTokens.MusicMetrics.waveformBarCount
    var barSpacing: CGFloat = DesignTokens.MusicMetrics.waveformBarSpacing
    /// Fraction of the bounding box's smaller dimension left as empty
    /// margin on each side — see DesignTokens.MusicMetrics
    /// .waveformContentInset for why this is an estimate, not a
    /// measurement.
    var contentInset: CGFloat = DesignTokens.MusicMetrics.waveformContentInset

    @State private var pulse = false

    var body: some View {
        GeometryReader { proxy in
            let margin = min(proxy.size.width, proxy.size.height) * contentInset
            let availableWidth = proxy.size.width - margin * 2
            let availableHeight = proxy.size.height - margin * 2

            let totalSpacing = CGFloat(barCount - 1) * barSpacing
            let barWidth = max(1, (availableWidth - totalSpacing) / CGFloat(barCount))

            HStack(alignment: .center, spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: barWidth, height: barHeight(for: index, containerHeight: availableHeight))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
        }
        .onAppear { setPulsing(isPlaying) }
        .onChange(of: isPlaying) {
            setPulsing(isPlaying)
        }
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

    /// Six per-bar heights as a FRACTION of the container height, not an
    /// absolute point value — so this scales correctly whether it's
    /// rendered at 16pt tall (compact) or 24pt tall (expanded) instead of
    /// clipping or looking tiny at the other size. Values are offset per
    /// bar so they don't move in lockstep, reading as a natural waveform
    /// rather than a synced blink.
    private func barHeight(for index: Int, containerHeight: CGFloat) -> CGFloat {
        guard pulse else { return containerHeight * 0.35 }
        let fractions: [CGFloat] = [0.45, 0.85, 0.65, 1.0, 0.55, 0.75]
        return containerHeight * fractions[index % fractions.count]
    }
}
