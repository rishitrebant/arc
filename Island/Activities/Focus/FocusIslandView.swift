import SwiftUI

/// Renders `FocusActivity`: a purple moon on the left and "On" / "Off"
/// on the right, in the shared status pill. One layout — hovering
/// doesn't change it.
struct FocusIslandView: View {

    @ObservedObject var activity: FocusActivity

    private typealias Metrics = DesignTokens.StatusPillMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var pillSize: CGSize {
        activity.compactSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - pillSize.width) / 2
    }

    private var tint: Color {
        activity.isFocused
            ? DesignTokens.Color.focusAccent
            : DesignTokens.Color.secondaryText
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: DesignTokens.Shape.compactTopRadius,
                bottomRadius: DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: pillSize.width, height: pillSize.height)
            .position(x: canvasSize.width / 2, y: pillSize.height / 2)

            HStack(spacing: 0) {

                Image(systemName: activity.isFocused ? "moon.fill" : "moon")
                    .font(.system(size: Metrics.glyphSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)

                Spacer(minLength: 0)

                Text(activity.isFocused ? "On" : "Off")
                    .font(Metrics.labelFont)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Metrics.edgePadding)
            .frame(width: pillSize.width, height: pillSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(AnimationTokens.stateUpdate, value: activity.isFocused)
    }
}
