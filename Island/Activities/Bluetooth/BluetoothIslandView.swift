import SwiftUI

/// The oval device card, shared by every "a device did something" moment
/// (Bluetooth connect / disconnect, sound output change): a fully round
/// pill with the notch overlapping its top, the device glyph on the left,
/// ONE line of text beneath the notch, and a status ring on the right.
///
/// Content is centred in the whole height — there is no reserved band for
/// the notch, because the single line of text already sits below it.
struct DeviceCardLayout<Trailing: View>: View {

    let symbolName: String
    let title: String
    let status: String
    @ViewBuilder let trailing: Trailing

    private typealias Metrics = DesignTokens.AirDropMetrics

    var body: some View {

        HStack(spacing: 0) {

            DeviceIconView(
                symbolName: symbolName,
                diameter: Metrics.expandedIconSize,
                showsDisc: false
            )
            .padding(.leading, Metrics.expandedEdgePadding)

            // "Name connected" — the name in white, the status dimmed,
            // one line, truncating the name first.
            (
                Text(title)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                +
                Text(" \(status)")
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            )
            .font(DesignTokens.Typography.title)
            .tracking(DesignTokens.Typography.letterSpacingTight)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, Metrics.expandedIconToTextGap)
            // Sits just under the notch's bottom edge.
            .offset(y: 3)

            trailing
                .frame(
                    width: Metrics.expandedIconSize,
                    height: Metrics.expandedIconSize
                )
                .padding(.leading, Metrics.expandedIconToTextGap)
                .padding(.trailing, Metrics.expandedEdgePadding)
        }
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

/// Renders `BluetoothActivity`: the oval device card on connect and on
/// disconnect. Hovering turns the ring into a Disconnect button.
///
/// One layout only (compact size == expanded size), so hovering never
/// resizes it — `isExpanded` just means "the cursor is on it".
struct BluetoothIslandView: View {

    @ObservedObject var activity: BluetoothActivity
    let isExpanded: Bool

    private typealias Metrics = DesignTokens.AirDropMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var cardSize: CGSize {
        activity.expandedSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - cardSize.width) / 2
    }

    private var symbolName: String {
        activity.device?.symbolName ?? "dot.radiowaves.left.and.right"
    }

    private var deviceName: String {
        activity.device?.name ?? "Bluetooth Device"
    }

    private var isConnected: Bool {
        activity.phase == .connected
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: cardSize.height / 2,
                bottomRadius: cardSize.height / 2
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: cardSize.width, height: cardSize.height)
            .position(x: canvasSize.width / 2, y: cardSize.height / 2)

            DeviceCardLayout(
                symbolName: symbolName,
                title: deviceName,
                status: isConnected ? "connected" : "disconnected"
            ) {
                trailing
            }
            .frame(width: cardSize.width, height: cardSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(AnimationTokens.stateUpdate, value: activity.phase)
        .animation(AnimationTokens.stateUpdate, value: activity.battery)
        .animation(AnimationTokens.stateUpdate, value: isExpanded)
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
                    .frame(
                        width: Metrics.expandedIconSize,
                        height: Metrics.expandedIconSize
                    )
                    .background(
                        Circle().fill(DesignTokens.Color.deviceIconBackground)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityLabel("Disconnect")
            .transition(.scale(scale: 0.6).combined(with: .opacity))

        } else if isConnected, let level = activity.battery?.headline {

            let tint = level <= 20
                ? DesignTokens.Color.lowBatteryAccent
                : DesignTokens.Color.chargingAccent

            DeviceStatusRing(
                fraction: Double(level) / 100,
                tint: tint
            ) {
                Text("\(level)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.primaryText)
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
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.tick() }
            }
    }
}
