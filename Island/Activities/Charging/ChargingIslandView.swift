import SwiftUI

/// Renders `ChargingActivity`: the island widens past the notch and
/// shows "Charging" on the left, battery percentage and a green battery
/// on the right — the iPhone charging moment, on the Mac notch.
///
/// Same fixed-canvas architecture as `MusicIslandView` and
/// `FileDropIslandView`: this view's outer frame is always the shared
/// canvas size, and the visible pill positions itself inside it. That's
/// what keeps ownership changes between activities from re-triggering
/// the window-recentering flakiness the other activities already solved.
///
/// There is only one layout. `isExpanded` is accepted because the
/// `Activity` contract passes it, but hovering doesn't change this pill.
struct ChargingIslandView: View {

    @ObservedObject var activity: ChargingActivity
    let isExpanded: Bool

    private typealias Metrics = DesignTokens.ChargingMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var pillSize: CGSize {
        CGSize(
            width: Metrics.compactWidth,
            height: Metrics.compactHeight
        )
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - pillSize.width) / 2
    }

    private var label: String {
        activity.isFullyCharged ? "Charged" : "Charging"
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

            content
                .frame(width: pillSize.width, height: pillSize.height)
                .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(AnimationTokens.stateUpdate, value: activity.batteryPercent)
        .animation(AnimationTokens.stateUpdate, value: activity.isFullyCharged)
    }

    // MARK: - Content
    //
    // Left/right flanks sit outside the physical notch. Edge padding is
    // the same 10pt token every other compact pill uses.

    private var content: some View {

        HStack(alignment: .center, spacing: 0) {

            Text(label)
                .font(Metrics.labelFont)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .lineLimit(1)
                .fixedSize()

            Spacer(minLength: 0)

            HStack(spacing: Metrics.percentToBatterySpacing) {

                Text("\(activity.batteryPercent)%")
                    .font(Metrics.percentFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.chargingAccent)
                    .lineLimit(1)
                    .fixedSize()

                BatteryGlyph(percent: activity.batteryPercent)
            }
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }
}
