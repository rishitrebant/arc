import SwiftUI

/// The island's waveform — six thin bars that swing on their own phases
/// while music plays and rest low when it's paused.
///
/// This is the clock-driven `LiveWaveform` under its original name, so
/// the compact pill, the expanded view and the shared pill all draw the
/// SAME waveform. (The first version started its motion with a
/// `repeatForever` animation, which a morph or transition in progress
/// could swallow, leaving the bars frozen.)
struct Waveform: View {

    var isPlaying: Bool
    var color: Color = DesignTokens.Color.musicAccent
    var barCount: Int = DesignTokens.MusicMetrics.waveformBarCount
    var barSpacing: CGFloat = DesignTokens.MusicMetrics.waveformBarSpacing
    var contentInset: CGFloat = DesignTokens.MusicMetrics.waveformContentInset

    var body: some View {
        LiveWaveform(
            isPlaying: isPlaying,
            color: color,
            barCount: barCount,
            barSpacing: barSpacing,
            contentInset: contentInset
        )
    }
}

/// A waveform driven by the clock instead of by a repeating animation.
///
/// `Waveform` starts its motion with a `repeatForever` animation, which
/// an ambient transaction (a morph in progress, a transition) can swallow
/// so the bars sit still. This one recomputes the bar heights from the
/// time on every frame while `isPlaying`, so it always moves when it
/// should — used where the view appears mid-transition (the shared pill).
struct LiveWaveform: View {

    var isPlaying: Bool
    var color: Color = DesignTokens.Color.musicAccent
    var barCount: Int = DesignTokens.MusicMetrics.waveformBarCount
    var barSpacing: CGFloat = DesignTokens.MusicMetrics.waveformBarSpacing
    var contentInset: CGFloat = DesignTokens.MusicMetrics.waveformContentInset

    var body: some View {

        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { context in

            let time = context.date.timeIntervalSinceReferenceDate

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
                            .frame(
                                width: barWidth,
                                height: availableHeight * fraction(index: index, time: time)
                            )
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
    }

    /// 0.35 resting; while playing each bar swings between roughly 0.3
    /// and 1.0 on its own phase, so the bars never move in lockstep.
    private func fraction(index: Int, time: TimeInterval) -> CGFloat {

        guard isPlaying else { return 0.35 }

        let speeds: [Double] = [5.2, 6.4, 4.6, 7.0, 5.8, 6.1]
        let phase = Double(index) * 1.3

        let wave = (sin(time * speeds[index % speeds.count] + phase) + 1) / 2

        return 0.3 + 0.7 * CGFloat(wave)
    }
}
