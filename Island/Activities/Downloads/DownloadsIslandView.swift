import SwiftUI

/// A circular progress ring with a download arrow in it. With a known
/// fraction it fills; without one it spins as a short arc.
struct DownloadRing: View {

    let fraction: Double?
    let isComplete: Bool
    let diameter: CGFloat
    let lineWidth: CGFloat

    @State private var spin = false

    private var tint: Color {
        isComplete ? DesignTokens.Color.chargingAccent : DesignTokens.Color.airDropAccent
    }

    var body: some View {

        ZStack {

            Circle()
                .stroke(tint.opacity(0.28), lineWidth: lineWidth)

            if isComplete {

                Circle()
                    .trim(from: 0, to: 1)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))

            } else if let fraction {

                Circle()
                    .trim(from: 0, to: max(0.02, fraction))
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.4), value: fraction)

            } else {

                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .onAppear {
                        withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                            spin = true
                        }
                    }
            }

            Image(systemName: isComplete ? "checkmark" : "arrow.down")
                .font(.system(size: diameter * 0.42, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Renders `DownloadsActivity`:
///   - compact: the progress ring on the left, the percentage on the right
///   - expanded (on hover): a larger ring, the file name, and the sizes
struct DownloadsIslandView: View {

    @ObservedObject var activity: DownloadsActivity
    let isExpanded: Bool

    private typealias Compact = DesignTokens.StatusPillMetrics
    private typealias Expanded = DesignTokens.DownloadsMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visibleSize: CGSize {
        isExpanded ? activity.expandedSize : activity.compactSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - visibleSize.width) / 2
    }

    private var title: String {

        if activity.isComplete { return "Download Complete" }

        guard let first = activity.items.first else { return "Downloading" }

        return activity.items.count > 1
            ? "\(first.name) and \(activity.items.count - 1) more"
            : first.name
    }

    private var subtitle: String {

        if activity.isComplete { return "Saved to Downloads" }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file

        let done = formatter.string(fromByteCount: activity.totalBytes)

        let expected = activity.items.reduce(Int64(0)) { $0 + ($1.totalBytes ?? 0) }

        if activity.fraction != nil, expected > 0 {
            return "\(done) of \(formatter.string(fromByteCount: expected))"
        }

        return "\(done) downloaded"
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
        .animation(AnimationTokens.stateUpdate, value: activity.isComplete)
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(spacing: 0) {

            DownloadRing(
                fraction: activity.fraction,
                isComplete: activity.isComplete,
                diameter: Compact.iconSlot,
                lineWidth: Expanded.compactRingLineWidth
            )

            Spacer(minLength: 0)

            if activity.isComplete {

                Text("Done")
                    .font(Compact.labelFont)
                    .foregroundStyle(DesignTokens.Color.chargingAccent)
                    .fixedSize()

            } else if let fraction = activity.fraction {

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(Compact.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.airDropAccent)
                    .fixedSize()
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, Compact.edgePadding)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout — nothing renders here.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            HStack(spacing: Expanded.iconToTextGap) {

                DownloadRing(
                    fraction: activity.fraction,
                    isComplete: activity.isComplete,
                    diameter: Expanded.ringSize,
                    lineWidth: Expanded.ringLineWidth
                )

                VStack(alignment: .leading, spacing: 2) {

                    Text(title)
                        .font(DesignTokens.Typography.title)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Text(subtitle)
                        .font(Expanded.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 0)

                HStack(spacing: Expanded.buttonSpacing) {

                    if activity.canOpenBrowser, !activity.isComplete {
                        actionButton(
                            symbol: "arrow.up.forward.app",
                            label: "Go to download"
                        ) {
                            activity.openBrowser()
                        }
                    }

                    actionButton(
                        symbol: "folder",
                        label: "Show in Finder"
                    ) {
                        activity.showInFinder()
                    }
                }
            }
            .padding(.horizontal, Expanded.edgePadding)
            .frame(maxHeight: .infinity)
            .padding(.bottom, Expanded.bottomPadding)
        }
    }

    private func actionButton(
        symbol: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: Expanded.buttonGlyphSize, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Expanded.buttonSize, height: Expanded.buttonSize)
                .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
        }
        .buttonStyle(DownloadPressStyle())
        .accessibilityLabel(label)
        .help(label)
    }
}

/// Same press feedback as the other island buttons.
private struct DownloadPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
