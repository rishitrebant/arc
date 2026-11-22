import SwiftUI

/// Renders `PrivacyActivity`: the glyph of every sensor in use on the
/// left (each in its iOS colour), and the name of the one that just
/// turned on on the right.
struct PrivacyIslandView: View {

    @ObservedObject var activity: PrivacyActivity

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

    /// Fixed order, so glyphs never swap places when one is added.
    private var glyphs: [(PrivacySensors, String, Color)] {
        [
            (.camera, "video.fill", DesignTokens.Color.cameraIndicator),
            (.microphone, "mic.fill", DesignTokens.Color.microphoneIndicator),
            (.screen, "record.circle", DesignTokens.Color.screenIndicator)
        ]
        .filter { activity.sensors.contains($0.0) }
    }

    private var label: String {
        if activity.newest.contains(.camera) { return "Camera" }
        if activity.newest.contains(.screen) { return "Screen" }
        return "Mic"
    }

    private var labelColor: Color {
        if activity.newest.contains(.camera) { return DesignTokens.Color.cameraIndicator }
        if activity.newest.contains(.screen) { return DesignTokens.Color.screenIndicator }
        return DesignTokens.Color.microphoneIndicator
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

                HStack(spacing: 4) {
                    ForEach(glyphs, id: \.1) { _, symbol, color in
                        Image(systemName: symbol)
                            .font(.system(size: Metrics.glyphSize, weight: .semibold))
                            .foregroundStyle(color)
                            .frame(height: Metrics.iconSlot)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

                Spacer(minLength: 0)

                Text(label)
                    .font(Metrics.labelFont)
                    .foregroundStyle(labelColor)
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
        .animation(AnimationTokens.stateUpdate, value: activity.sensors.rawValue)
    }
}
