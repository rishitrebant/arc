import SwiftUI

/// Renders `AudioOutputActivity`:
///   - compact: the device glyph on the left, a blue check on the right
///   - expanded (on hover): the device glyph on a disc, its name, and
///     "Sound Output"
///
/// Same fixed-canvas architecture as the other activities.
struct AudioOutputIslandView: View {

    @ObservedObject var activity: AudioOutputActivity
    let isExpanded: Bool

    private typealias Compact = DesignTokens.StatusPillMetrics
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

    private var symbol: String {
        activity.device?.symbolName ?? "speaker.wave.2.fill"
    }

    var body: some View {

        IslandMorphSurface(
            isExpanded: isExpanded,
            compactSize: activity.compactSize,
            expandedSize: activity.expandedSize
        ) {
            compactRow
        } expanded: {
            expandedPanel
        }
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(spacing: 0) {

            Device3DIcon(
                symbolName: symbol,
                name: activity.device?.name ?? "",
                size: Compact.iconSlot
            )
            .padding(.leading, -3)

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.chargingAccent)
                .frame(width: Compact.iconSlot, height: Compact.iconSlot)
        }
        .padding(.horizontal, Compact.edgePadding)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // The notch covers only the middle; this is just breathing room.
            Color.clear
                .frame(height: DesignTokens.DeviceCard.topInset)

            DeviceCardLayout(
                symbolName: symbol,
                title: activity.device?.name ?? "Speakers",
                status: "Sound Output"
            ) {
                DeviceStatusRing(fraction: 1, tint: DesignTokens.Color.chargingAccent) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.chargingAccent)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
