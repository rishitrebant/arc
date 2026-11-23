import SwiftUI

/// An activity that can also appear as a small detached bubble beside the
/// island while ANOTHER activity owns the notch — the Dynamic Island's
/// "minimal" presentation. This is how a running timer and playing music
/// can both be on screen at once.
@MainActor
protocol MinimalPresentable {
    func minimalView() -> AnyView
}

// MARK: - Bubble chrome

/// The black rounded square every minimal bubble sits on.
struct MinimalBubble<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(
                width: DesignTokens.BubbleMetrics.side,
                height: DesignTokens.BubbleMetrics.side
            )
            .background(
                RoundedRectangle(
                    cornerRadius: DesignTokens.BubbleMetrics.cornerRadius,
                    style: .continuous
                )
                .fill(DesignTokens.Color.islandBackground)
            )
    }
}

// MARK: - Timer

extension TimerActivity: MinimalPresentable {

    func minimalView() -> AnyView {
        AnyView(TimerMinimalBubble(activity: self))
    }
}

/// A progress ring with the clock's glyph inside — the iPhone's timer
/// bubble. Stopwatches have no end, so they show the glyph alone.
private struct TimerMinimalBubble: View {

    @ObservedObject var activity: TimerActivity

    private typealias Metrics = DesignTokens.BubbleMetrics

    private var slot: TimerSlot? {
        activity.activeSlots.first(where: \.countsDown)
            ?? activity.activeSlots.first
    }

    var body: some View {

        MinimalBubble {

            if let slot {

                ZStack {

                    if let progress = slot.progress {

                        Circle()
                            .stroke(slot.accent.opacity(0.28), lineWidth: Metrics.ringLineWidth)

                        Circle()
                            .trim(from: 0, to: max(0.02, progress))
                            .stroke(
                                slot.accent,
                                style: StrokeStyle(
                                    lineWidth: Metrics.ringLineWidth,
                                    lineCap: .round
                                )
                            )
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.4), value: progress)
                    }

                    Image(systemName: slot.glyph)
                        .font(.system(size: Metrics.glyphSize, weight: .semibold))
                        .foregroundStyle(slot.accent)
                        .symbolEffect(.pulse, isActive: slot.phase == .finished)
                }
                .frame(width: Metrics.contentSize, height: Metrics.contentSize)
                .opacity(slot.phase == .paused ? 0.55 : 1)
            }
        }
    }
}

// MARK: - Music

extension MusicActivity: MinimalPresentable {

    func minimalView() -> AnyView {
        AnyView(MusicMinimalBubble(activity: self))
    }
}

/// The album art as a small rounded square (or a note when there is none).
private struct MusicMinimalBubble: View {

    @ObservedObject var activity: MusicActivity

    private typealias Metrics = DesignTokens.BubbleMetrics

    var body: some View {

        MinimalBubble {

            Group {
                if let artwork = activity.playbackState?.artwork {
                    Image(nsImage: artwork)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: Metrics.glyphSize, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.musicAccent)
                }
            }
            .frame(width: Metrics.contentSize, height: Metrics.contentSize)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: Metrics.contentCornerRadius,
                    style: .continuous
                )
            )
            .opacity(activity.playbackState?.isPlaying == true ? 1 : 0.55)
        }
    }
}

// MARK: - Downloads

extension DownloadsActivity: MinimalPresentable {

    func minimalView() -> AnyView {
        AnyView(DownloadsMinimalBubble(activity: self))
    }
}

private struct DownloadsMinimalBubble: View {

    @ObservedObject var activity: DownloadsActivity

    var body: some View {

        MinimalBubble {
            DownloadRing(
                fraction: activity.fraction,
                isComplete: activity.isComplete,
                diameter: DesignTokens.BubbleMetrics.contentSize,
                lineWidth: DesignTokens.BubbleMetrics.ringLineWidth
            )
        }
    }
}
