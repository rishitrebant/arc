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

        IslandMorphSurface(
            isExpanded: isExpanded,
            compactSize: activity.compactSize,
            expandedSize: activity.expandedSize
        ) {
            compactRow
        } expanded: {
            expandedPanel
        }
        // Starting or ending the second clock resizes the pill smoothly
        // instead of snapping.
        .animation(AnimationTokens.shapeSpring, value: visibleSize.width)
        .animation(AnimationTokens.shapeSpring, value: slots.count)
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(spacing: 0) {

            if slots.count > 1 {

                ForEach(Array(slots.prefix(2).enumerated()), id: \.element.kind) { index, slot in

                    if index > 0 { Spacer(minLength: 0) }

                    compactClock(slot, glyphLeading: true)
                }

            } else if let slot = slots.first {

                Image(systemName: slot.glyph)
                    .font(.system(size: Metrics.compactGlyphSize, weight: .semibold))
                    .foregroundStyle(slot.accent)
                    .symbolEffect(.pulse, isActive: slot.phase == .finished)
                    .frame(width: Metrics.compactIconSlot, height: Metrics.compactIconSlot)
                .padding(.leading, slot.kind == .pomodoro ? 2 : -3)

                Spacer(minLength: 0)

                compactTime(slot)
            }
        }
        .padding(.horizontal, Metrics.compactEdgePadding)
    }

    private func compactClock(_ slot: TimerSlot, glyphLeading: Bool) -> some View {

        HStack(spacing: Metrics.compactGlyphToTime) {

            Image(systemName: slot.glyph)
                .font(.system(size: Metrics.compactGlyphSize, weight: .semibold))
                .foregroundStyle(slot.accent)
                .symbolEffect(.pulse, isActive: slot.phase == .finished)
                .frame(width: Metrics.compactIconSlot, height: Metrics.compactIconSlot)
                .padding(.leading, slot.kind == .pomodoro ? 2 : -3)

            compactTime(slot)
        }
    }

    private func compactTime(_ slot: TimerSlot) -> some View {

        Text(slot.phase == .finished ? "Done" : Self.format(slot.displaySeconds))
            .font(Metrics.compactTimeFont)
            .monospacedDigit()
            .foregroundStyle(slot.accent)
            .opacity(slot.phase == .paused ? 0.55 : 1)
            .lineLimit(1)
            .fixedSize()
            .contentTransition(.numericText(countsDown: slot.countsDown))
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
            .padding(.bottom, slots.contains { $0.kind == .pomodoro } ? 0 : Metrics.bottomPadding)

            // A running Pomodoro: its focus sound — pick it in one corner,
            // play or pause it in the other.
            if slots.contains(where: { $0.kind == .pomodoro }) {
                PomodoroSoundBar()
                    .padding(.horizontal, Metrics.expandedEdgePadding)
                    .frame(height: Metrics.soundBarHeight)
                    .padding(.bottom, 6)
            }
        }
        .overlay(alignment: .topLeading) {
            LauncherBackButton()
        }
    }

    // MARK: - Helpers

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

                    Image(systemName: slot.glyph)
                        .font(.system(size: Metrics.labelGlyphSize, weight: .semibold))

                    Text(slot.title)
                        .font(Metrics.labelFont)
                        .lineLimit(1)
                }
                .foregroundStyle(slot.accent)

                Text(TimerIslandView.format(slot.displaySeconds))
                    .font(dual ? Metrics.timeFontDual : Metrics.timeFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .opacity(isPaused ? 0.55 : 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText(countsDown: slot.countsDown))
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
                            foreground: slot.accent,
                            background: slot.accent.opacity(0.28)
                        ) {
                            slot.restart()
                        }
                    }

                } else {

                    controlButton(
                        symbol: isPaused ? "play.fill" : "pause.fill",
                        label: isPaused ? "Resume" : "Pause",
                        foreground: slot.accent,
                        background: slot.accent.opacity(0.28)
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
                .contentTransition(.symbolEffect(.replace))
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


/// The Pomodoro's focus sound: pick it (left), set how loud it is
/// (middle), play or pause it (right).
private struct PomodoroSoundBar: View {

    @ObservedObject private var player = FocusSoundPlayer.shared

    @AppStorage(AppSettings.Key.focusSound)
    private var sound = AppSettings.Default.focusSound
    @AppStorage(AppSettings.Key.focusSoundVolume)
    private var volume = AppSettings.Default.focusSoundVolume

    private var current: FocusSound {
        FocusSound(rawValue: sound) ?? .off
    }

    var body: some View {

        HStack(spacing: 10) {

            Menu {

                Picker("Sound", selection: $sound) {

                    Label("Off", systemImage: FocusSound.off.symbol)
                        .tag(FocusSound.off.rawValue)

                    ForEach([FocusSound.Group.nature, .cozy, .noise], id: \.rawValue) { group in
                        Section(group.rawValue) {
                            ForEach(FocusSound.allCases.filter { $0.group == group }) { option in
                                Label(option.title, systemImage: option.symbol)
                                    .tag(option.rawValue)
                            }
                        }
                    }
                }
                .pickerStyle(.inline)

            } label: {

                HStack(spacing: 5) {
                    Image(systemName: current.symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                    Text(current == .off ? "No sound" : current.title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .background(Capsule().fill(Color.white.opacity(0.09)))
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .onChange(of: sound) { _, _ in player.refresh() }

            // How loud — a slider, like the one on the Music card.
            HStack(spacing: 7) {

                Image(systemName: "speaker.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)

                ThinSlider(value: $volume, range: 0.05...1) {
                    player.refresh()
                }

                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            }
            .frame(maxWidth: .infinity)

            Button {

                if current == .off {
                    sound = FocusSound.rain.rawValue
                    player.resume()
                } else {
                    player.togglePaused()
                }

            } label: {
                Image(systemName: player.isAudible ? "pause.fill" : "play.fill")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 26, height: 24)
                    .background(Capsule().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isAudible ? "Pause sound" : "Play sound")
        }
    }
}
