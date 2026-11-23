import SwiftUI

/// Renders `LauncherActivity`: a full-size island panel with a Now
/// Playing row on top and three Clock-style tiles (Timer, Pomodoro,
/// Stopwatch) beneath. Timer and Pomodoro open a small setup page in the
/// same panel; Stopwatch starts immediately.
struct LauncherIslandView: View {

    @ObservedObject var activity: LauncherActivity
    @ObservedObject var music: MusicActivity
    @ObservedObject var clipboard: ClipboardHistory
    @ObservedObject var bluetooth: BluetoothActivity

    /// The clipboard row just copied — shows a check for a moment.
    @State private var copiedID: UUID?

    private typealias Metrics = DesignTokens.LauncherMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var panelSize: CGSize {
        activity.expandedSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - panelSize.width) / 2
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: DesignTokens.Shape.expandedTopRadius,
                bottomRadius: DesignTokens.Shape.expandedBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: panelSize.width, height: panelSize.height)
            .position(x: canvasSize.width / 2, y: panelSize.height / 2)

            VStack(spacing: 0) {

                // Reserves the physical notch cutout — nothing renders here.
                Color.clear
                    .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

                Group {
                    switch activity.page {
                    case .home:
                        homePage
                    case .timer:
                        timerPage
                    case .pomodoro:
                        pomodoroPage
                    case .clipboard:
                        clipboardPage
                    }
                }
                .transition(.opacity)
                .padding(.horizontal, Metrics.edgePadding)
                .padding(.bottom, Metrics.bottomPadding)
                .frame(maxHeight: .infinity)
            }
            .frame(width: panelSize.width, height: panelSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(.easeInOut(duration: 0.2), value: activity.page)
    }

    // MARK: - Home

    private var homePage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            nowPlayingRow

            HStack(spacing: Metrics.tileSpacing) {

                tile(
                    symbol: "timer",
                    title: "Timer",
                    tint: DesignTokens.Color.timerAccent
                ) {
                    activity.page = .timer
                }

                tile(
                    symbol: "brain.head.profile",
                    title: "Pomodoro",
                    tint: DesignTokens.Color.pomodoroAccent
                ) {
                    activity.page = .pomodoro
                }

                tile(
                    symbol: "stopwatch.fill",
                    title: "Stopwatch",
                    tint: DesignTokens.Color.timerAccent
                ) {
                    activity.startStopwatch()
                }

                tile(
                    symbol: "doc.on.clipboard.fill",
                    title: "Clipboard",
                    tint: DesignTokens.Color.capsLockAccent
                ) {
                    activity.page = .clipboard
                }
            }

            bluetoothRow
        }
    }

    // MARK: Bluetooth (subtle)

    /// One quiet line — device name and battery — for whatever is
    /// connected, the way iOS lists connected accessories. Absent when
    /// nothing is.
    @ViewBuilder
    private var bluetoothRow: some View {

        let devices = Array(bluetooth.connected.prefix(2))

        if !devices.isEmpty {

            HStack(spacing: 14) {

                ForEach(devices) { device in

                    HStack(spacing: 5) {

                        Image(systemName: device.symbolName)
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 11, weight: .medium))

                        Text(device.name)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        if let level = bluetooth.batteries[device.address]?.headline {

                            Text("\(level)%")
                                .monospacedDigit()
                                .foregroundStyle(
                                    level <= 20
                                        ? DesignTokens.Color.lowBatteryAccent
                                        : DesignTokens.Color.secondaryText
                                )
                        }
                    }
                }
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(DesignTokens.Color.secondaryText)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }

    // MARK: Now Playing

    private var nowPlayingRow: some View {

        HStack(spacing: 12) {

            if let state = music.playbackState {

                AlbumArtView(
                    image: state.artwork,
                    size: Metrics.artSize,
                    cornerRadius: Metrics.artCornerRadius
                )

                VStack(alignment: .leading, spacing: 2) {

                    Text(state.title)
                        .font(Metrics.titleFont)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)

                    Text(state.artist)
                        .font(Metrics.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                PlaybackButton(
                    systemName: state.isPlaying ? "pause.fill" : "play.fill",
                    action: { withAnimation { music.togglePlayPause() } },
                    size: 20,
                    buttonSize: Metrics.transportButtonSize
                )

                PlaybackButton(
                    systemName: "forward.fill",
                    action: { music.skipForward() },
                    size: 18,
                    buttonSize: Metrics.transportButtonSize
                )

            } else {

                RoundedRectangle(
                    cornerRadius: Metrics.artCornerRadius,
                    style: .continuous
                )
                .fill(DesignTokens.Color.deviceIconBackground)
                .frame(width: Metrics.artSize, height: Metrics.artSize)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }

                VStack(alignment: .leading, spacing: 2) {

                    Text("Not Playing")
                        .font(Metrics.titleFont)
                        .foregroundStyle(DesignTokens.Color.primaryText)

                    Text("Play something in Music or Spotify")
                        .font(Metrics.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
        .frame(height: Metrics.artSize)
    }

    private func tile(
        symbol: String,
        title: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            VStack(spacing: 6) {

                Image(systemName: symbol)
                    .font(.system(size: Metrics.tileGlyphSize, weight: .medium))
                    .foregroundStyle(tint)

                Text(title)
                    .font(Metrics.tileFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Metrics.tileHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Metrics.tileCornerRadius,
                    style: .continuous
                )
                .fill(DesignTokens.Color.deviceIconBackground)
            )
        }
        .buttonStyle(LauncherPressStyle())
    }

    // MARK: - Timer setup

    private let timerPresets = [1, 5, 10, 15, 25, 30]

    private var timerPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            header(
                title: "Timer",
                tint: DesignTokens.Color.timerAccent,
                startAction: { activity.startTimer() }
            )

            HStack(spacing: 8) {
                ForEach(timerPresets, id: \.self) { minutes in
                    chip(
                        minutes: minutes,
                        isSelected: activity.timerMinutes == minutes,
                        tint: DesignTokens.Color.timerAccent
                    ) {
                        activity.timerMinutes = minutes
                    }
                }
            }

            stepperRow(
                title: "Custom",
                value: $activity.timerMinutes,
                range: 1...999
            )
        }
    }

    // MARK: - Pomodoro setup

    private var pomodoroPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            header(
                title: "Pomodoro",
                tint: DesignTokens.Color.pomodoroAccent,
                startAction: { activity.startPomodoro() }
            )

            stepperRow(
                title: "Focus",
                value: $activity.focusMinutes,
                range: 1...180
            )

            stepperRow(
                title: "Break",
                value: $activity.breakMinutes,
                range: 1...60
            )
        }
    }

    // MARK: - Clipboard

    private var clipboardPage: some View {

        VStack(spacing: Metrics.sectionSpacing - 4) {

            HStack(spacing: 10) {

                Button {
                    activity.page = .home
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                        .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
                }
                .buttonStyle(LauncherPressStyle())
                .accessibilityLabel("Back")

                Text("Clipboard")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)

                if !clipboard.entries.isEmpty {
                    Button {
                        clipboard.clear()
                    } label: {
                        Text("Clear")
                            .font(Metrics.tileFont)
                            .foregroundStyle(DesignTokens.Color.primaryText)
                            .padding(.horizontal, 14)
                            .frame(height: Metrics.controlSize)
                            .background(Capsule().fill(DesignTokens.Color.deviceIconBackground))
                    }
                    .buttonStyle(LauncherPressStyle())
                }
            }

            if clipboard.entries.isEmpty {

                Spacer(minLength: 0)

                Text(AppSettings.keepClipboardHistory
                     ? "Things you copy will show up here"
                     : "Clipboard history is turned off in Settings")
                    .font(Metrics.subtitleFont)
                    .foregroundStyle(DesignTokens.Color.secondaryText)

                Spacer(minLength: 0)

            } else {

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(clipboard.entries) { entry in
                            clipboardRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func clipboardRow(_ entry: ClipboardEntry) -> some View {

        Button {

            activity.copyBack(entry)

            copiedID = entry.id

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if copiedID == entry.id { copiedID = nil }
            }

        } label: {

            HStack(spacing: 10) {

                Image(systemName: entry.symbolName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.capsLockAccent)
                    .frame(width: 22)

                Text(entry.title)
                    .font(Metrics.tileFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if copiedID == entry.id {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.chargingAccent)
                        .transition(.opacity)
                }
            }
            .animation(AnimationTokens.stateUpdate, value: copiedID)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                RoundedRectangle(
                    cornerRadius: 12,
                    style: .continuous
                )
                .fill(DesignTokens.Color.deviceIconBackground)
            )
        }
        .buttonStyle(LauncherPressStyle())
    }

    // MARK: - Setup components

    private func header(
        title: String,
        tint: Color,
        startAction: @escaping () -> Void
    ) -> some View {

        HStack(spacing: 10) {

            Button {
                activity.page = .home
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                    .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
            }
            .buttonStyle(LauncherPressStyle())
            .accessibilityLabel("Back")

            Text(title)
                .font(Metrics.titleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer(minLength: 0)

            Button(action: startAction) {
                Text("Start")
                    .font(Font.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, 20)
                    .frame(height: Metrics.startButtonHeight)
                    .background(Capsule().fill(tint))
            }
            .buttonStyle(LauncherPressStyle())
        }
    }

    private func chip(
        minutes: Int,
        isSelected: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Text("\(minutes)m")
                .font(Metrics.tileFont)
                .foregroundStyle(isSelected ? Color.black : DesignTokens.Color.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: Metrics.chipHeight)
                .background(
                    Capsule().fill(
                        isSelected ? tint : DesignTokens.Color.deviceIconBackground
                    )
                )
        }
        .buttonStyle(LauncherPressStyle())
    }

    private func stepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {

        HStack(spacing: 10) {

            Text(title)
                .font(Metrics.titleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer(minLength: 0)

            stepperButton(symbol: "minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            }

            Text("\(value.wrappedValue) min")
                .font(Metrics.valueFont)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(minWidth: 72)
                .contentTransition(.numericText())

            stepperButton(symbol: "plus") {
                value.wrappedValue = min(range.upperBound, value.wrappedValue + 1)
            }
        }
        .animation(AnimationTokens.stateUpdate, value: value.wrappedValue)
    }

    private func stepperButton(
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
        }
        .buttonStyle(LauncherPressStyle())
    }
}

/// Same press feedback as the other island buttons.
private struct LauncherPressStyle: ButtonStyle {

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
