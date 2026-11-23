import SwiftUI

/// Renders `CapsLockActivity`: a Caps Lock glyph on the left and
/// "On" / "Off" on the right, in AirDrop's compact pill. Hovering doesn't
/// change it — there is only one layout.
struct CapsLockIslandView: View {

    @ObservedObject var activity: CapsLockActivity

    private typealias Compact = DesignTokens.AirDropMetrics

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
        activity.isCapsLockOn
            ? DesignTokens.Color.capsLockAccent
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

                Image(systemName: activity.isCapsLockOn ? "capslock.fill" : "capslock")
                    .font(.system(size: DesignTokens.CapsLockMetrics.glyphSize, weight: .semibold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: Compact.compactIconSize, height: Compact.compactIconSize)
                .padding(.leading, -3)

                Spacer(minLength: 0)

                Text(activity.isCapsLockOn ? "On" : "Off")
                    .font(DesignTokens.CapsLockMetrics.statusFont)
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, Compact.compactEdgePadding)
            .frame(width: pillSize.width, height: pillSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(AnimationTokens.stateUpdate, value: activity.isCapsLockOn)
    }
}
