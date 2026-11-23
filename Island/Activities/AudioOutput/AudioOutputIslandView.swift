import SwiftUI

/// Renders `AudioOutputActivity`:
///   - compact: the device glyph on the left, a blue check on the right
///   - expanded (on hover): the device glyph on a disc, its name, and
///     "Sound Output"
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
    }

    private var compactRow: some View {

        HStack(spacing: 0) {

            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: Compact.glyphSize + 1, weight: .medium))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .symbolEffect(.bounce, value: activity.device?.id)
                .frame(width: Compact.iconSlot, height: Compact.iconSlot)

            Spacer(minLength: 0)

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.capsLockAccent)
                .frame(width: Compact.iconSlot, height: Compact.iconSlot)
        }
        .padding(.horizontal, Compact.edgePadding)
    }

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout — nothing renders here.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            HStack(spacing: Expanded.iconToTextGap) {

                DeviceIconView(
                    symbolName: symbol,
                    diameter: Expanded.iconSize
                )

                VStack(alignment: .leading, spacing: 2) {

                    Text(activity.device?.name ?? "Speakers")
                        .font(DesignTokens.Typography.title)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("Sound Output")
                        .font(Expanded.statusFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, Expanded.edgePadding)
            .frame(maxHeight: .infinity)
            .padding(.bottom, Expanded.bottomPadding)
        }
    }
}
