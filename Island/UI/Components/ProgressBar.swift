import SwiftUI

/// Playback progress bar with elapsed/remaining time labels, matching the
/// "2:10 ─────── -2:35" layout measured in "Music Expanded.png".
struct ProgressBar: View {
    var elapsed: TimeInterval
    var duration: TimeInterval
    var width: CGFloat = DesignTokens.MusicMetrics.progressBarWidth

    private var progress: CGFloat {
        guard duration > 0 else { return 0 }
        return min(max(elapsed / duration, 0), 1)
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Text(format(elapsed))
                .font(DesignTokens.Typography.timestamp)
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(DesignTokens.Color.primaryText)
                        .frame(width: proxy.size.width * progress)
                }
            }
            .frame(width: width, height: 5)

            Text("-" + format(max(duration - elapsed, 0)))
                .font(DesignTokens.Typography.timestamp)
                .tracking(DesignTokens.Typography.letterSpacingTight)
                .foregroundStyle(DesignTokens.Color.secondaryText)
        }
    }

    private func format(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
