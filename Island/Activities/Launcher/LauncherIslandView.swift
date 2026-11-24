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
    @ObservedObject var youtube: YouTubeActivity

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
        .animation(.easeInOut(duration: 0.2), value: bluetooth.connected.isEmpty)
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

    // MARK: Bluetooth

    /// The connected device, like the row Control Center shows: the
    /// glyph on a soft disc, the name, "Connected · 85%" beneath it, and
    /// a quiet Disconnect button. Absent when nothing is connected.
    @ViewBuilder
    private var bluetoothRow: some View {

        if let device = bluetooth.connected.first {

            let battery = bluetooth.batteries[device.address]
            let extra = bluetooth.connected.count - 1

            HStack(spacing: 10) {

                DeviceIconView(
                    symbolName: device.symbolName,
                    diameter: 28
                )

                VStack(alignment: .leading, spacing: 1) {

                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    HStack(spacing: 5) {

                        Text(extra > 0 ? "Connected · +\(extra) more" : "Connected")

                        if let detail = battery?.detail {

                            Text("· \(detail)")

                        } else if let level = battery?.headline {

                            BatteryGlyph(
                                percent: level,
                                tint: level <= 20
                                    ? DesignTokens.Color.lowBatteryAccent
                                    : DesignTokens.Color.primaryText,
                                showsBolt: false
                            )
                            .scaleEffect(0.7)
                            .frame(width: 18, height: 9)

                            Text("\(level)%")
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    bluetooth.disconnect(address: device.address)
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 24)
                        .background(
                            Capsule().fill(DesignTokens.Color.deviceIconBackground)
                        )
                }
                .buttonStyle(LauncherPressStyle())
            }
            .padding(.horizontal, 10)
            .frame(height: Metrics.deviceCardHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Metrics.tileCornerRadius,
                    style: .continuous
                )
                .fill(Color.white.opacity(0.07))
            )
            .transition(.opacity)
        }
    }

    // MARK: Now Playing

    /// ONE thing at a time: a YouTube video while one is playing,
    /// otherwise the last song from Music / Spotify.
    @ViewBuilder
    private var nowPlayingRow: some View {

        if let video = youtube.video, video.isPlaying {
            youtubeRow(video)
        } else {
            musicRow
        }
    }

    // MARK: YouTube

    private func youtubeRow(_ video: WebVideoState) -> some View {

        HStack(spacing: 12) {

            // 16:9 thumbnail with a small YouTube mark in the corner.
            ZStack(alignment: .bottomLeading) {

                Group {
                    if let thumbnail = video.thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Rectangle().fill(DesignTokens.Color.deviceIconBackground)
                    }
                }
                .frame(width: 80, height: 45)
                .clipShape(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                )

                YouTubeLogoMark(height: 9)
                    .padding(4)
            }

            VStack(alignment: .leading, spacing: 2) {

                Text(video.title)
                    .font(Metrics.titleFont)
                    .tracking(DesignTokens.Typography.letterSpacingTight)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(1)

                HStack(spacing: 5) {

                    if video.isLive {
                        Circle()
                            .fill(DesignTokens.Color.youtubeRed)
                            .frame(width: 6, height: 6)
                    }

                    Text(video.isLive
                         ? "LIVE · \(video.channel)"
                         : video.channel)
                        .font(Metrics.subtitleFont)
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            PlaybackButton(
                systemName: video.isPlaying ? "pause.fill" : "play.fill",
                action: { youtube.togglePlayPause() },
                size: 20,
                buttonSize: Metrics.transportButtonSize
            )

            // Forward 5 s on a recorded video; a live stream has no
            // forward, so the second button rewinds it instead.
            PlaybackButton(
                systemName: video.isLive ? "gobackward.15" : "goforward.5",
                action: {
                    video.isLive ? youtube.skipBack() : youtube.skipForward()
                },
                size: 18,
                buttonSize: Metrics.transportButtonSize
            )
        }
        .frame(height: Metrics.artSize)
    }

    // MARK: Music

    private var musicRow: some View {

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
                range: 1...999,
                onSubmit: { activity.startTimer() }
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
                range: 1...180,
                onSubmit: { activity.startPomodoro() }
            )

            stepperRow(
                title: "Break",
                value: $activity.breakMinutes,
                range: 1...60,
                onSubmit: { activity.startPomodoro() }
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
        range: ClosedRange<Int>,
        onSubmit: @escaping () -> Void = {}
    ) -> some View {

        HStack(spacing: 10) {

            Text(title)
                .font(Metrics.titleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            Spacer(minLength: 0)

            stepperButton(symbol: "minus") {
                value.wrappedValue = max(range.lowerBound, value.wrappedValue - 1)
            }

            // Click the number and type it — or use − and +. Return
            // starts it.
            HStack(spacing: 4) {

                TextField("", value: value, format: .number)
                    .textFieldStyle(.plain)
                    .font(Metrics.valueFont)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .frame(width: 44)
                    .onSubmit {
                        value.wrappedValue = min(max(value.wrappedValue, range.lowerBound), range.upperBound)
                        onSubmit()
                    }
                    // A typed 0 or 5000 snaps into range.
                    .onChange(of: value.wrappedValue) { _, typed in
                        let clamped = min(max(typed, range.lowerBound), range.upperBound)
                        if clamped != typed { value.wrappedValue = clamped }
                    }

                Text("min")
                    .font(Metrics.subtitleFont)
                    .foregroundStyle(DesignTokens.Color.secondaryText)
            }
            .padding(.horizontal, 12)
            .frame(height: Metrics.controlSize)
            .background(
                Capsule().fill(DesignTokens.Color.deviceIconBackground.opacity(0.7))
            )

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
