import SwiftUI

/// Renders `TimerActivity`:
///   - compact: one clock shows a timer glyph on the left and the time on
///     the right; with a timer AND a stopwatch running, the timer sits
///     left of the notch and the stopwatch right of it
///   - expanded (on hover): a row per clock — label, large time, and
///     Cancel / Pause-Resume discs (Stop / Repeat once a countdown ends)
///
/// Same fixed-canvas architecture as `BluetoothIslandView`.
struct TimerIslandView: View {

    @ObservedObject var activity: TimerActivity
    let isExpanded: Bool

    private typealias Metrics = DesignTokens.TimerMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visibleSize: CGSize {
        isExpanded ? activity.expandedSize : activity.compactSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - visibleSize.width) / 2
    }

    private var slots: [TimerSlot] {
        activity.activeSlots
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
        // Starting or ending the second clock resizes the pill smoothly
        // instead of snapping.
        .animation(AnimationTokens.shapeSpring, value: slots.count)
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(spacing: 0) {

            if slots.count > 1 {

                ForEach(Array(slots.enumerated()), id: \.element.kind) { index, slot in

                    if index > 0 { Spacer(minLength: 0) }

                    compactClock(slot, glyphLeading: true)
                }

            } else if let slot = slots.first {

                Image(systemName: Self.glyph(for: slot))
                    .font(.system(size: Metrics.compactGlyphSize, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.timerAccent)
                    .symbolEffect(.pulse, isActive: slot.phase == .finished)
                    .frame(width: Metrics.compactIconSlot, height: Metrics.compactIconSlot)

                Spacer(minLength: 0)

                compactTime(slot)
            }
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }

    private func compactClock(_ slot: TimerSlot, glyphLeading: Bool) -> some View {

        HStack(spacing: Metrics.compactGlyphToTime) {

            Image(systemName: Self.glyph(for: slot))
                .font(.system(size: Metrics.compactGlyphSize, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.timerAccent)
                .symbolEffect(.pulse, isActive: slot.phase == .finished)
                .frame(width: Metrics.compactIconSlot, height: Metrics.compactIconSlot)

            compactTime(slot)
        }
    }

    private func compactTime(_ slot: TimerSlot) -> some View {

        Text(slot.phase == .finished ? "Done" : Self.format(slot.displaySeconds))
            .font(Metrics.compactTimeFont)
            .monospacedDigit()
            .foregroundStyle(DesignTokens.Color.timerAccent)
            .opacity(slot.phase == .paused ? 0.55 : 1)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText(countsDown: slot.kind == .countdown))
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        let dual = slots.count > 1

        return VStack(spacing: 0) {

            // Reserves the physical notch cutout — nothing renders here.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            VStack(spacing: Metrics.rowSpacing) {

                ForEach(slots, id: \.kind) { slot in
                    TimerRow(slot: slot, dual: dual)
                }
            }
            .padding(.horizontal, Metrics.expandedEdgePadding)
            .frame(maxHeight: .infinity)
            .padding(.bottom, Metrics.bottomPadding)
        }
    }

    // MARK: - Helpers

    static func glyph(for slot: TimerSlot) -> String {
        if slot.phase == .finished { return "bell.fill" }
        return slot.kind == .stopwatch ? "stopwatch.fill" : "timer"
    }

    /// `m:ss`, or `h:mm:ss` from one hour up.
    static func format(_ total: Int) -> String {
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}

/// One clock's row in the expanded panel. Observes its own slot so the
/// time and the buttons update live.
private struct TimerRow: View {

    @ObservedObject var slot: TimerSlot
    let dual: Bool

    private typealias Metrics = DesignTokens.TimerMetrics

    private var isFinished: Bool { slot.phase == .finished }
    private var isPaused: Bool { slot.phase == .paused }

    private var title: String {
        if isFinished { return "Timer Done" }
        return slot.kind == .stopwatch ? "Stopwatch" : "Timer"
    }

    private var buttonSize: CGFloat {
        dual ? Metrics.buttonSizeDual : Metrics.buttonSize
    }

    private var buttonGlyph: CGFloat {
        dual ? Metrics.buttonGlyphSizeDual : Metrics.buttonGlyphSize
    }

    var body: some View {

        HStack(spacing: 0) {

            VStack(alignment: .leading, spacing: 0) {

                HStack(spacing: 4) {

                    Image(systemName: TimerIslandView.glyph(for: slot))
                        .font(.system(size: Metrics.labelGlyphSize, weight: .semibold))

                    Text(title)
                        .font(Metrics.labelFont)
                        .lineLimit(1)
                }
                .foregroundStyle(DesignTokens.Color.timerAccent)

                Text(TimerIslandView.format(slot.displaySeconds))
                    .font(dual ? Metrics.timeFontDual : Metrics.timeFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .opacity(isPaused ? 0.55 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(countsDown: slot.kind == .countdown))
            }

            Spacer(minLength: 12)

            HStack(spacing: Metrics.buttonSpacing) {

                controlButton(
                    symbol: "xmark",
                    label: isFinished ? "Stop" : "Cancel",
                    foreground: DesignTokens.Color.primaryText,
                    background: DesignTokens.Color.controlDisc
                ) {
                    slot.cancel()
                }

                if isFinished {

                    if slot.kind == .countdown {
                        controlButton(
                            symbol: "arrow.clockwise",
                            label: "Repeat",
                            foreground: DesignTokens.Color.timerAccent,
                            background: DesignTokens.Color.timerAccent.opacity(0.28)
                        ) {
                            slot.restart()
                        }
                    }

                } else {

                    controlButton(
                        symbol: isPaused ? "play.fill" : "pause.fill",
                        label: isPaused ? "Resume" : "Pause",
                        foreground: DesignTokens.Color.timerAccent,
                        background: DesignTokens.Color.timerAccent.opacity(0.28)
                    ) {
                        slot.togglePause()
                    }
                }
            }
        }
        .animation(AnimationTokens.stateUpdate, value: slot.phase)
    }

    private func controlButton(
        symbol: String,
        label: String,
        foreground: Color,
        background: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: buttonGlyph, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: buttonSize, height: buttonSize)
                .background(Circle().fill(background))
        }
        .buttonStyle(TimerPressStyle())
        .accessibilityLabel(label)
    }
}

/// Same press feedback as the Bluetooth Disconnect button.
private struct TimerPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
