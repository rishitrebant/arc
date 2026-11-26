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

    /// Wider than the shared canvas (the pill is 411 wide), so this view
    /// widens its own frame rather than changing the shared constant
    /// other activities — the shelf included — depend on.
    private var canvasSize: CGSize {
        CGSize(
            width: max(
                DesignTokens.sharedCanvasSize.width,
                Metrics.compactWidth
            ),
            height: DesignTokens.sharedCanvasSize.height
        )
    }

    private var pillSize: CGSize {
        activity.compactSize
    }

    private var hasDevices: Bool {
        !activity.deviceLevels.isEmpty
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
                bottomRadius: hasDevices
                    ? DesignTokens.Shape.expandedBottomRadius
                    : DesignTokens.Shape.compactBottomRadius
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

        VStack(spacing: 0) {

            HStack(alignment: .center, spacing: 0) {

                HStack(spacing: Metrics.percentToBatterySpacing + 2) {

                    DeviceStatusRing(
                        fraction: Double(activity.batteryPercent) / 100,
                        tint: batteryTint
                    ) {
                        EmptyView()
                    }
                    .frame(width: Metrics.ringSize - 6, height: Metrics.ringSize - 6)

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
            .frame(height: Metrics.compactHeight)

            if hasDevices {
                deviceRow
            }
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }

    /// What else is running low: each connected Bluetooth device and
    /// its level, in one quiet line.
    private var deviceRow: some View {

        HStack(spacing: 14) {

            ForEach(activity.deviceLevels) { device in

                HStack(spacing: 5) {

                    Image(systemName: device.symbolName)
                        .font(.system(size: 11, weight: .medium))

                    Text("\(device.level)%")
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(
                            device.level <= 20
                                ? DesignTokens.Color.lowBatteryAccent
                                : DesignTokens.Color.primaryText
                        )
                }
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .lineLimit(1)
                .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: Metrics.deviceRowHeight)
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
