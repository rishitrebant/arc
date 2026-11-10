import SwiftUI

/// Renders `LowBatteryActivity`: a red battery and percentage on the
/// left, a yellow "Low Power Mode" button on the right. Clicking
/// anywhere on the pill turns Low Power Mode on.
///
/// Same fixed-canvas architecture as `ChargingIslandView`: the outer
/// frame is always the shared canvas size and the visible pill positions
/// itself inside it. One layout; `isExpanded` is accepted for the
/// `Activity` contract but hovering doesn't change this pill.
struct LowBatteryIslandView: View {

    @ObservedObject var activity: LowBatteryActivity
    let isExpanded: Bool

    private typealias Metrics = DesignTokens.LowBatteryMetrics

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

    /// Red while it's a warning, yellow once Low Power Mode is on —
    /// the same colour change the iPhone battery makes.
    private var batteryTint: Color {
        activity.phase == .enabled
            ? DesignTokens.Color.lowPowerModeAccent
            : DesignTokens.Color.lowBatteryAccent
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
                .contentShape(Rectangle())
                .onTapGesture {
                    activity.enableLowPowerMode()
                }
                .accessibilityAddTraits(.isButton)
                .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(AnimationTokens.stateUpdate, value: activity.phase)
        .animation(AnimationTokens.stateUpdate, value: activity.batteryPercent)
    }

    // MARK: - Content

    private var content: some View {

        HStack(alignment: .center, spacing: 0) {

            HStack(spacing: Metrics.percentToBatterySpacing) {

                BatteryGlyph(
                    percent: activity.batteryPercent,
                    tint: batteryTint,
                    showsBolt: false
                )

                Text("\(activity.batteryPercent)%")
                    .font(Metrics.percentFont)
                    .monospacedDigit()
                    .foregroundStyle(batteryTint)
                    .lineLimit(1)
                    .fixedSize()
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }

    @ViewBuilder
    private var trailing: some View {

        switch activity.phase {

        case .prompt:

            actionButton("Low Power Mode", opacity: 1)

        case .enabling:

            actionButton("Turning On…", opacity: 0.55)

        case .enabled:

            HStack(spacing: Metrics.confirmationIconSpacing) {

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))

                Text("Low Power On")
                    .font(Metrics.buttonFont)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(DesignTokens.Color.lowPowerModeAccent)
        }
    }

    /// The yellow capsule. Purely visual — the tap is handled by the
    /// whole pill (see `body`), so the click target is generous.
    private func actionButton(_ title: String, opacity: Double) -> some View {

        Text(title)
            .font(Metrics.buttonFont)
            .foregroundStyle(.black)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Metrics.buttonHorizontalPadding)
            .frame(height: Metrics.buttonHeight)
            .background(
                Capsule()
                    .fill(DesignTokens.Color.lowPowerModeAccent)
            )
            .opacity(opacity)
    }
}
