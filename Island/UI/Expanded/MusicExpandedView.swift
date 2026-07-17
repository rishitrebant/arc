import SwiftUI

/// The expanded, hover-triggered presentation of Music.
///
/// This is deliberately NOT a responsive layout. The expanded island is
/// always exactly 390×200 — a fixed physical object, not a window that
/// reflows. Every element below has an explicit, named coordinate in
/// `Layout`, positioned with `.position(x:y:)` against that fixed canvas.
/// The ONLY things that vary between songs are the title and artist text
/// (title truncates rather than reflowing anything around it). Nothing
/// else moves, regardless of content — there is no `Spacer()` anywhere in
/// this file driving primary layout.
///
/// Coordinates are derived from the Figma measurements (390×200 canvas,
/// 24pt side/bottom padding, 48pt notch-clearance top padding, 56pt
/// artwork, 242pt progress track, 38pt-derived symmetric control spacing)
/// and treated as the source of truth.
struct MusicExpandedView: View {
    @ObservedObject var activity: MusicActivity

    @Environment(\.islandNamespace) private var namespace

    /// The fixed coordinate grid for the expanded card. Every value here is
    /// a deliberate placement, not a computed/responsive one — this is the
    /// "hardware spec sheet" for the layout. All positions are CENTER
    /// points, matching how `.position(x:y:)` places a view.
    private enum Layout {
        static let canvasWidth: CGFloat = DesignTokens.MusicMetrics.expandedWidth   // 390
        static let canvasHeight: CGFloat = DesignTokens.MusicMetrics.expandedHeight // 200

        // Content bounds: 24pt sides/bottom, 48pt notch-clearance top.
        static let contentLeft: CGFloat = DesignTokens.MusicMetrics.expandedEdgePadding   // 24
        static let contentRight: CGFloat = canvasWidth - DesignTokens.MusicMetrics.expandedEdgePadding // 366
        static let contentTop: CGFloat = DesignTokens.MusicMetrics.expandedTopPadding     // 48

        // Album artwork — fixed frame, top-left of the content area.
        static let artSize: CGFloat = DesignTokens.MusicMetrics.albumArtSize // 56
        static let artCenter = CGPoint(x: contentLeft + artSize / 2, y: contentTop + artSize / 2) // (52, 76)

        // Waveform — fixed frame, top-right of the content area, top-aligned with artwork.
        static let waveformSize = CGSize(width: DesignTokens.MusicMetrics.waveformIconWidth, height: 16) // (43, 16)
        static let waveformCenter = CGPoint(x: contentRight - waveformSize.width / 2, y: contentTop + waveformSize.height / 2) // (344.5, 56)

        // Title/artist block — the only flexible content. Fixed box between
        // artwork and waveform; title truncates rather than resizing this box.
        static let textLeft: CGFloat = contentLeft + artSize + DesignTokens.Spacing.md // 104
        static let textRight: CGFloat = waveformCenter.x - waveformSize.width / 2 - DesignTokens.Spacing.sm // 307
        static let textWidth: CGFloat = textRight - textLeft // 203
        static let textHeight: CGFloat = artSize - 12 // 44 — leaves room to top-align with artwork
        static let textCenter = CGPoint(x: textLeft + textWidth / 2, y: contentTop + textHeight / 2) // (205.5, 70)

        // Progress row — elapsed label, track, remaining label all
        // independently fixed, so none of them shift based on digit count.
        static let progressRowY: CGFloat = contentTop + artSize + 8 // 112
        static let timeLabelSize = CGSize(width: 34, height: 15)
        static let trackWidth: CGFloat = DesignTokens.MusicMetrics.progressBarWidth // 242
        static let trackHeight: CGFloat = 5
        static let elapsedLabelCenter = CGPoint(x: contentLeft + timeLabelSize.width / 2, y: progressRowY + timeLabelSize.height / 2) // (41, 119.5)
        static let trackCenter = CGPoint(
            x: contentLeft + timeLabelSize.width + DesignTokens.Spacing.xs + trackWidth / 2,
            y: elapsedLabelCenter.y
        ) // (187, 119.5)
        static let remainingLabelCenter = CGPoint(
            x: trackCenter.x + trackWidth / 2 + DesignTokens.Spacing.xs + timeLabelSize.width / 2,
            y: elapsedLabelCenter.y
        ) // (333, 119.5)

        // Controls row — back / play-pause / forward, perfectly symmetric
        // about the content area's horizontal center, plus AirPlay fixed at
        // the trailing edge in the same column as the waveform above it.
        static let controlsRowY: CGFloat =
            canvasHeight
            - DesignTokens.MusicMetrics.expandedEdgePadding
            - playSize / 2
        static let playSize: CGFloat = 34
        static let controlCenterSpacing: CGFloat = 63 // center-to-center, identical on both sides — symmetric by construction
        static let contentCenterX: CGFloat = (contentLeft + contentRight) / 2 // 195

        static let playCenter = CGPoint(x: contentCenterX, y: controlsRowY)
        static let backCenter = CGPoint(x: contentCenterX - controlCenterSpacing, y: controlsRowY)
        static let forwardCenter = CGPoint(x: contentCenterX + controlCenterSpacing, y: controlsRowY)
        static let airplayCenter = CGPoint(x: waveformCenter.x, y: controlsRowY) // same column as the waveform
    }

    var body: some View {
        ZStack {
            IslandShape.body(
                topRadius: DesignTokens.Shape.expandedTopRadius,
                bottomRadius: DesignTokens.Shape.expandedBottomRadius
            )
                .fill(DesignTokens.Color.islandBackground)
                .islandMatchedGeometry(id: "islandBody", namespace: namespace)

            albumArt
            textBlock
            waveform
            progressRow
            controlsRow
        }
        .frame(width: Layout.canvasWidth, height: Layout.canvasHeight)
    }

    // MARK: - Fixed elements

    private var albumArt: some View {
        AlbumArtView(
            image: activity.playbackState?.artwork,
            size: Layout.artSize,
            cornerRadius: DesignTokens.MusicMetrics.albumArtCornerRadius
        )
        .islandMatchedGeometry(id: "albumArt", namespace: namespace)
        .position(Layout.artCenter)
    }

    private var waveform: some View {
        Waveform(isPlaying: activity.playbackState?.isPlaying ?? false)
            .frame(width: Layout.waveformSize.width, height: Layout.waveformSize.height)
            .islandMatchedGeometry(id: "waveform", namespace: namespace)
            .position(Layout.waveformCenter)
    }

    /// The only variable content in the layout. Fixed box — title truncates
    /// with a tail ellipsis rather than ever resizing this box or shifting
    /// anything around it.
    private var textBlock: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            Text(activity.playbackState?.title ?? "")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Text(activity.playbackState?.artist ?? "")
                .font(DesignTokens.Typography.subtitle)
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(width: Layout.textWidth, height: Layout.textHeight, alignment: .topLeading)
        .transition(AnimationTokens.contentTransition(insertDelay: 0.02, removeDelay: 0.04))
        .position(Layout.textCenter)
    }

    /// Elapsed label, track, and remaining label are each independently
    /// fixed — the track never shifts based on how wide the elapsed label's
    /// text happens to render, since its position doesn't derive from the
    /// label's width at all.
    private var progressRow: some View {
        Group {
            Text(formatted(activity.playbackState?.elapsed ?? 0))
                .font(DesignTokens.Typography.timestamp.monospacedDigit())
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .frame(width: Layout.timeLabelSize.width, height: Layout.timeLabelSize.height, alignment: .leading)
                .position(Layout.elapsedLabelCenter)

            progressTrack
                .frame(width: Layout.trackWidth, height: Layout.trackHeight)
                .position(Layout.trackCenter)

            Text("-" + formatted(remaining))
                .font(DesignTokens.Typography.timestamp.monospacedDigit())
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .frame(width: Layout.timeLabelSize.width, height: Layout.timeLabelSize.height, alignment: .trailing)
                .position(Layout.remainingLabelCenter)
        }
        .transition(AnimationTokens.contentTransition(insertDelay: 0.05, removeDelay: 0.02))
    }

    private var progressTrack: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.2))
                Capsule()
                    .fill(DesignTokens.Color.primaryText)
                    .frame(width: proxy.size.width * progressFraction)
            }
        }
    }

    private var controlsRow: some View {
        Group {
            PlaybackButton(systemName: "backward.fill", action: activity.skipBackward, size: 16)
                .opacity(0.7)
                .position(Layout.backCenter)

            PlaybackButton(
                systemName: (activity.playbackState?.isPlaying ?? false) ? "pause.fill" : "play.fill",
                action: activity.togglePlayPause,
                size: 20
            )
            .frame(width: Layout.playSize, height: Layout.playSize)
            .background(Circle().fill(Color.white.opacity(0.14)))
            .position(Layout.playCenter)

            PlaybackButton(systemName: "forward.fill", action: activity.skipForward, size: 16)
                .opacity(0.7)
                .position(Layout.forwardCenter)

            // AirPlay-style routing icon — fixed in the same column as the
            // waveform above it, matches "Music Hover.png" / "Music Expanded.png".
            Image(systemName: "airplayaudio")
                .font(.system(size: 18))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Layout.waveformSize.width, height: Layout.playSize)
                .position(Layout.airplayCenter)
        }
        .transition(AnimationTokens.contentTransition(insertDelay: 0.08, removeDelay: 0))
    }

    // MARK: - Derived values (not layout — just formatting)

    private var remaining: TimeInterval {
        max((activity.playbackState?.duration ?? 0) - (activity.playbackState?.elapsed ?? 0), 0)
    }

    private var progressFraction: CGFloat {
        guard let state = activity.playbackState, state.duration > 0 else { return 0 }
        return min(max(state.elapsed / state.duration, 0), 1)
    }

    private func formatted(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
