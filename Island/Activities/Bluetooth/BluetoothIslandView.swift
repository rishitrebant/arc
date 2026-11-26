import SwiftUI

/// The device card: the glyph on the left, "Connected" over the device's
/// name in the middle, and a status ring (the battery, or a check) on the
/// right — like the AirPods card on an iPhone.
struct DeviceCardLayout<Trailing: View>: View {

    let symbolName: String
    let title: String
    let status: String
    @ViewBuilder let trailing: Trailing

    private typealias Card = DesignTokens.DeviceCard

    var body: some View {

        HStack(spacing: Card.gap) {

            Device3DIcon(symbolName: symbolName, name: title, size: Card.iconSize)

            VStack(alignment: .leading, spacing: 2) {

                Text(status)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)

                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .tracking(DesignTokens.Typography.letterSpacingTight)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            trailing
                .frame(width: Card.trailingSize, height: Card.trailingSize)
        }
        .padding(.horizontal, Card.edgePadding)
    }
}

/// A circular progress ring with something in the middle — the battery
/// (or a check) on the right of a device card.
struct DeviceStatusRing<Center: View>: View {

    /// 0...1
    let fraction: Double
    let tint: Color
    @ViewBuilder let center: Center

    var body: some View {

        ZStack {

            Circle()
                .stroke(tint.opacity(0.3), lineWidth: DesignTokens.AirDropMetrics.ringLineWidth + 1.5)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, fraction)))
                .stroke(
                    tint,
                    style: StrokeStyle(
                        lineWidth: DesignTokens.AirDropMetrics.ringLineWidth + 1.5,
                        lineCap: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.4), value: fraction)

            center
        }
    }
}

/// Renders `BluetoothActivity`: a card when a device connects (and while
/// you hover it), settling to a small pill — the glyph on one side, the
/// battery ring on the other — until it goes away.
struct BluetoothIslandView: View {

    @ObservedObject var activity: BluetoothActivity
    let isExpanded: Bool

    private typealias Metrics = DesignTokens.AirDropMetrics

    private var symbolName: String {
        activity.device?.symbolName ?? "dot.radiowaves.left.and.right"
    }

    private var deviceName: String {
        activity.device?.name ?? "Bluetooth Device"
    }

    private var isConnected: Bool {
        activity.phase == .connected
    }

    private var level: Int? {
        isConnected ? activity.battery?.headline : nil
    }

    private var ringTint: Color {
        (level ?? 100) <= 20
            ? DesignTokens.Color.lowBatteryAccent
            : DesignTokens.Color.chargingAccent
    }

    var body: some View {

        IslandMorphSurface(
            isExpanded: isExpanded || activity.showsCard,
            compactSize: activity.pillSize,
            expandedSize: activity.cardSize
        ) {
            pill
        } expanded: {
            card
        }
        .animation(AnimationTokens.stateUpdate, value: activity.phase)
        .animation(AnimationTokens.stateUpdate, value: activity.battery)
        .animation(AnimationTokens.stateUpdate, value: isExpanded)
    }

    // MARK: - Pill

    private var pill: some View {

        HStack(spacing: 0) {

            Device3DIcon(symbolName: symbolName, name: deviceName, size: Metrics.compactIconSize + 2)

            Spacer(minLength: 0)

            if let level {
                DeviceStatusRing(fraction: Double(level) / 100, tint: ringTint) { EmptyView() }
                    .frame(width: Metrics.compactIconSize - 2, height: Metrics.compactIconSize - 2)
            } else {
                Image(systemName: isConnected ? "checkmark.circle" : "xmark.circle")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(isConnected ? DesignTokens.Color.airDropAccent : DesignTokens.Color.secondaryText)
            }
        }
        .padding(.horizontal, Metrics.compactEdgePadding + 2)
    }

    // MARK: - Card

    private var card: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            DeviceCardLayout(
                symbolName: symbolName,
                title: deviceName,
                status: isConnected ? "Connected" : "Disconnected"
            ) {
                trailing
            }
            .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Right-hand status

    @ViewBuilder
    private var trailing: some View {

        if isConnected, isExpanded {

            Button {
                activity.disconnectDevice()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .frame(width: DesignTokens.DeviceCard.trailingSize, height: DesignTokens.DeviceCard.trailingSize)
                    .background(
                        Circle().fill(DesignTokens.Color.deviceIconBackground)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Disconnect")
            .transition(.scale(scale: 0.6).combined(with: .opacity))

        } else if let level {

            DeviceStatusRing(fraction: Double(level) / 100, tint: ringTint) {
                Text("\(level)%")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(ringTint)
            }
            .transition(.opacity)

        } else {

            DeviceStatusRing(
                fraction: 1,
                tint: isConnected
                    ? DesignTokens.Color.airDropAccent
                    : DesignTokens.Color.secondaryText
            ) {
                Image(systemName: isConnected ? "checkmark" : "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(
                        isConnected
                            ? DesignTokens.Color.airDropAccent
                            : DesignTokens.Color.secondaryText
                    )
            }
            .transition(.opacity)
        }
    }
}

/// Subtle press feedback — a slight shrink and dim, like Apple's own
/// capsule buttons — instead of the flat, unresponsive `.plain` style.
struct PressableButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
