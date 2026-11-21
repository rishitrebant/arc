import SwiftUI

/// Renders `BluetoothActivity`:
///   - compact: the device icon on the left, a green "connected" check
///     on the right — the same pill geometry as AirDrop's
///   - expanded (on hover): a lit, dimensional device icon, the name
///     and status, and a Disconnect button
///
/// Same fixed-canvas architecture as `MusicIslandView` and
/// `FileDropIslandView`: the outer frame is always the shared canvas
/// size and the visible pill positions itself inside it, morphing
/// between compact and expanded with `AnimationTokens.shapeMorph`.
struct BluetoothIslandView: View {

    @ObservedObject var activity: BluetoothActivity
    let isExpanded: Bool

    private typealias Compact = DesignTokens.AirDropMetrics
    private typealias Expanded = DesignTokens.BluetoothMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visibleSize: CGSize {
        isExpanded ? activity.expandedSize : activity.compactSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - visibleSize.width) / 2
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
                topRadius: isExpanded
                    ? DesignTokens.Shape.expandedTopRadius
                    : DesignTokens.Shape.compactTopRadius,
                bottomRadius: isExpanded
                    ? DesignTokens.Shape.expandedBottomRadius
                    : DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: visibleSize.width, height: visibleSize.height)
            .position(x: canvasSize.width / 2, y: visibleSize.height / 2)

            Group {
                if isExpanded {
                    expandedPanel
                } else {
                    compactRow
                }
            }
            .frame(width: visibleSize.width, height: visibleSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(
            AnimationTokens.shapeMorph(isExpanding: isExpanded),
            value: isExpanded
        )
        .animation(AnimationTokens.stateUpdate, value: activity.phase)
    }

    // MARK: - Compact
    //
    // Same positions as AirDrop's compact pill: 20pt content, 10pt in
    // from the outer edge, vertically centred.

    private var compactRow: some View {

        ZStack {

            DeviceIconView(
                symbolName: symbolName,
                diameter: Compact.compactIconSize,
                showsDisc: false
            )
            // One gentle bounce when the device appears — a single
            // short animation, not a loop.
            .symbolEffect(.bounce, value: activity.device?.address)
            .position(
                x: Compact.compactEdgePadding + Compact.compactIconSize / 2,
                y: Compact.compactContentCenterY
            )

            Image(systemName: isConnected
                  ? "checkmark.circle.fill"
                  : "xmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(
                    isConnected
                        ? DesignTokens.Color.chargingAccent
                        : DesignTokens.Color.secondaryText
                )
                .frame(
                    width: Compact.compactIconSize,
                    height: Compact.compactIconSize
                )
                .position(
                    x: Compact.compactWidth
                        - Compact.compactEdgePadding
                        - Compact.compactIconSize / 2,
                    y: Compact.compactContentCenterY
                )
        }
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout — nothing renders here.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            HStack(spacing: Expanded.iconToTextGap) {

                DeviceIconView(
                    symbolName: symbolName,
                    diameter: Expanded.iconSize
                )

                // Name + status
                VStack(alignment: .leading, spacing: 2) {

                    Text(deviceName)
                        .font(DesignTokens.Typography.title)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(isConnected ? "Connected" : "Disconnected")
                        .font(Expanded.statusFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }

                Spacer(minLength: 0)

                if isConnected {
                    disconnectButton
                }
            }
            .padding(.horizontal, Expanded.edgePadding)
            .frame(maxHeight: .infinity)
            .padding(.bottom, Expanded.bottomPadding)
        }
    }

    private var disconnectButton: some View {

        Button {
            activity.disconnectDevice()
        } label: {
            Text("Disconnect")
                .font(Expanded.buttonFont)
                .foregroundStyle(DesignTokens.Color.primaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Expanded.buttonHorizontalPadding)
                .frame(height: Expanded.buttonHeight)
                .background(
                    Capsule()
                        .fill(DesignTokens.Color.deviceIconBackground)
                )
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Subtle press feedback — a slight shrink and dim, like Apple's own
/// capsule buttons — instead of the flat, unresponsive `.plain` style.
private struct PressableButtonStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
