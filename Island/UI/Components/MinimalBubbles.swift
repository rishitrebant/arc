import SwiftUI

/// An activity that can also appear as a small detached bubble beside the
/// island while ANOTHER activity owns the notch — the Dynamic Island's
/// "minimal" presentation. This is how a running timer and playing music
/// can both be on screen at once.
@MainActor
protocol MinimalPresentable {

    /// The detached rounded-square bubble, for when the activity that
    /// owns the notch can't share it.
    func minimalView() -> AnyView

    /// How wide this activity's half of a shared pill needs to be.
    var earWidth: CGFloat { get }

    /// This activity's half of a shared pill — the pill is one even
    /// capsule split by the notch, one activity on each side.
    func earView(side: EarSide) -> AnyView
}

/// Which side of the notch a half of a shared pill sits on.
enum EarSide {
    case leading
    case trailing
}

/// A shared pill's content: one activity left of the notch, one right,
/// the notch itself between them.
struct SplitIslandContent: View {

    let leading: AnyView
    let trailing: AnyView
    let earWidth: CGFloat

    var body: some View {

        HStack(spacing: 0) {

            leading
                .frame(width: earWidth, height: DesignTokens.TimerMetrics.compactHeight)

            Color.clear
                .frame(width: DesignTokens.FileDropMetrics.notchWidth)

            trailing
                .frame(width: earWidth, height: DesignTokens.TimerMetrics.compactHeight)
        }
        .frame(height: DesignTokens.TimerMetrics.compactHeight)
    }
}

enum Ear {

    /// Edge padding. Slightly more than a bare pill's 10pt because the
    /// shared pill's outer corners flare and its content is optically
    /// closer to the edge.
    static let edge: CGFloat = 12

    /// A 20pt slot whose glyph is ~14pt leaves ~3pt of air on each
    /// side; pulling the outer edge in by this much makes the VISIBLE
    /// padding match the text on the other side.
    static let glyphAir: CGFloat = 3

    static let slot: CGFloat = 20
    static let gap: CGFloat = 5
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

    var earWidth: CGFloat {

        let hasHours = activeSlots.first.map { $0.displaySeconds >= 3600 } ?? false

        return Ear.edge + Ear.slot + Ear.gap
            + (hasHours
               ? DesignTokens.TimerMetrics.splitTimeWidthHours
               : DesignTokens.TimerMetrics.splitTimeWidth)
            + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(TimerEar(activity: self, side: side))
    }
}

/// The timer's half of a shared pill: its glyph at the outer edge and
/// the time beside it.
private struct TimerEar: View {

    @ObservedObject var activity: TimerActivity
    let side: EarSide

    var body: some View {

        if let slot = activity.activeSlots.first {

            let glyph = Image(systemName: slot.glyph)
                .font(.system(size: DesignTokens.TimerMetrics.compactGlyphSize, weight: .semibold))
                .foregroundStyle(slot.accent)
                .symbolEffect(.pulse, isActive: slot.phase == .finished)
                .frame(width: Ear.slot, height: Ear.slot)

            let time = Text(slot.phase == .finished
                            ? "Done"
                            : TimerIslandView.format(slot.displaySeconds))
                .font(DesignTokens.TimerMetrics.compactTimeFont)
                .monospacedDigit()
                .foregroundStyle(slot.accent)
                .opacity(slot.phase == .paused ? 0.55 : 1)
                .lineLimit(1)
                .fixedSize()
                .contentTransition(.numericText(countsDown: slot.countsDown))

            HStack(spacing: Ear.gap) {
                if side == .leading {
                    glyph
                        .padding(.leading, -Ear.glyphAir)
                    time
                } else {
                    time
                    glyph
                        .padding(.trailing, -Ear.glyphAir)
                }
            }
            .padding(.horizontal, Ear.edge)
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: side == .leading ? .leading : .trailing
            )
        }
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

    var earWidth: CGFloat {
        Ear.edge + Ear.slot + Ear.gap + Ear.slot + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(MusicEar(activity: self, side: side))
    }
}

/// Music's half of a shared pill: the album art and the waveform, the
/// same two things its own compact pill shows.
private struct MusicEar: View {

    @ObservedObject var activity: MusicActivity
    let side: EarSide

    /// The album's dominant colour — what Music's own pill tints its
    /// waveform with — so a shared pill matches it instead of falling
    /// back to the default yellow.
    @State private var accent = DesignTokens.Color.musicAccent

    /// Changes when the track or its artwork does.
    private var artworkKey: String {
        let state = activity.playbackState
        return "\(state?.title ?? "")|\(state?.artist ?? "")|\(state?.artwork != nil)"
    }

    private func refreshAccent() {
        accent = ArtworkColorExtractor.dominantColor(
            from: activity.playbackState?.artwork,
            fallback: DesignTokens.Color.musicAccent
        )
    }

    var body: some View {

        HStack(spacing: Ear.gap) {

            AlbumArtView(
                image: activity.playbackState?.artwork,
                size: Ear.slot,
                cornerRadius: DesignTokens.MusicMetrics.compactIconCornerRadius
            )

            LiveWaveform(
                isPlaying: activity.playbackState?.isPlaying ?? false,
                color: accent
            )
            .frame(width: Ear.slot, height: Ear.slot)
            // The waveform keeps ~3pt of its own margin inside its slot;
            // trim it so the visible edge gap equals the art's on the
            // other side.
            .padding(.trailing, -Ear.glyphAir)
        }
        .onAppear { refreshAccent() }
        .onChange(of: artworkKey) { _, _ in refreshAccent() }
        .padding(.horizontal, Ear.edge)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: side == .leading ? .leading : .trailing
        )
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

    var earWidth: CGFloat {
        Ear.edge + Ear.slot + Ear.gap + 30 + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(DownloadsEar(activity: self, side: side))
    }
}

private struct DownloadsEar: View {

    @ObservedObject var activity: DownloadsActivity
    let side: EarSide

    var body: some View {

        HStack(spacing: Ear.gap) {

            DownloadRing(
                fraction: activity.fraction,
                isComplete: activity.isComplete,
                diameter: Ear.slot,
                lineWidth: DesignTokens.DownloadsMetrics.compactRingLineWidth
            )

            if let fraction = activity.fraction {
                Text("\(Int((fraction * 100).rounded()))%")
                    .font(DesignTokens.StatusPillMetrics.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.airDropAccent)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Ear.edge)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: side == .leading ? .leading : .trailing
        )
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
