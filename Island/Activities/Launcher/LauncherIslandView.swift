import SwiftUI
import ImageIO

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
    @ObservedObject var timer: TimerActivity

    /// The clipboard row just copied — shows a check for a moment.
    @State private var copiedID: UUID?

    @State private var clipboardQuery = ""
    @State private var lastPanelSize: CGSize = .zero

    @AppStorage("teleprompterScript") private var teleScript = ""
    @AppStorage("teleprompterSpeed") private var teleSpeed = 34.0
    @State private var teleRunning = false
    @State private var telePaused = false
    @State private var teleOffset: CGFloat = 0
    @State private var teleTextHeight: CGFloat = 0

    /// Bounces when the panel grows; eases, without bounce, when it shrinks.
    private var panelAnimation: Animation {
        panelSize.height >= lastPanelSize.height && panelSize.width >= lastPanelSize.width
            ? AnimationTokens.expandSpring
            : .smooth(duration: 0.28)
    }
    @Namespace private var clockSegmentSpace
    @StateObject private var camera = CameraController()
    @StateObject private var stats = SystemStats()
    @ObservedObject private var keepAwake = KeepAwake.shared
    @State private var showNoteHistory = false
    @FocusState private var noteFocused: Bool
    @ObservedObject private var notes = NoteStore.shared

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
                // Either side of the notch: on the home page that's the
                // volume and the water / screen-time readouts.
                if activity.page == .home {
                    LauncherTopBar(activity: activity)
                } else {
                    Color.clear
                        .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)
                }

                Group {
                    switch activity.page {
                    case .home:
                        homePage
                    case .clock:
                        clockPage
                    case .pomodoro:
                        pomodoroPage
                    case .tools:
                        toolsPage
                    case .camera:
                        cameraPage
                    case .activity:
                        activityPage
                    case .teleprompter:
                        teleprompterPage
                    case .clipboard:
                        clipboardPage
                    case .notes:
                        notesPage
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
        .animation(panelAnimation, value: panelSize)
        .onChange(of: panelSize) { _, new in lastPanelSize = new }
        .animation(.easeInOut(duration: 0.2), value: bluetooth.connected.isEmpty)
    }

    // MARK: - Home

    private var homePage: some View {

        VStack(spacing: Metrics.sectionSpacing) {
            homeContent
        }
    }

    @ViewBuilder
    private var homeContent: some View {

        nowPlayingRow

        ForEach(Array(timer.activeSlots.prefix(2)), id: \.kind) { slot in
            LauncherTimerRow(slot: slot)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
        }

        HStack(spacing: Metrics.tileSpacing) {

            tile(symbol: "clock.fill", title: "Clock", tint: DesignTokens.Color.timerAccent) {
                activity.page = .clock
            }

            tile(symbol: "brain.head.profile", title: "Pomodoro", tint: DesignTokens.Color.pomodoroAccent) {
                activity.page = .pomodoro
            }

            tile(symbol: "doc.on.clipboard.fill", title: "Clipboard", tint: DesignTokens.Color.capsLockAccent) {
                activity.page = .clipboard
            }

            tile(symbol: "note.text", title: "Notes", tint: NoteActivity.accent) {
                activity.page = .notes
            }

            tile(symbol: "square.grid.2x2.fill", title: "Tools", tint: Color(red: 0.69, green: 0.32, blue: 0.87)) {
                activity.page = .tools
            }
        }

        bluetoothRow
    }

    // MARK: Bluetooth

    /// The connected device: its 3D icon, name and state, the battery as
    /// a ring, and a quiet Disconnect. Absent when nothing is connected.
    @ViewBuilder
    private var bluetoothRow: some View {

        if let device = bluetooth.connected.first {

            let battery = bluetooth.batteries[device.address]
            let extra = bluetooth.connected.count - 1
            let level = battery?.headline

            HStack(spacing: 12) {

                Device3DIcon(symbolName: device.symbolName, name: device.name, size: 30)

                VStack(alignment: .leading, spacing: 1) {

                    Text(device.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(
                        battery?.detail
                            ?? (extra > 0 ? "Connected · +\(extra) more" : "Connected")
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .lineLimit(1)
                }

                Spacer(minLength: 6)

                if let level {
                    DeviceStatusRing(
                        fraction: Double(level) / 100,
                        tint: level <= 20 ? DesignTokens.Color.lowBatteryAccent : DesignTokens.Color.chargingAccent
                    ) {
                        Text("\(level)")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.Color.primaryText)
                    }
                    .frame(width: 28, height: 28)
                }

                Button {
                    bluetooth.disconnect(address: device.address)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
                }
                .buttonStyle(LauncherPressStyle())
                .accessibilityLabel("Disconnect")
            }
            .padding(.horizontal, 12)
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

                if video.isYouTube == true || (video.isYouTube == nil && video.siteHost == nil) {
                    YouTubeLogoMark(height: 9)
                        .padding(4)
                } else {
                    SiteIconView(video: video, size: 16)
                        .padding(2)
                }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { activity.openNowPlayingCard() }

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
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { activity.openNowPlayingCard() }

                Spacer(minLength: 8)

                PlaybackButton(
                    systemName: "backward.fill",
                    action: { music.skipBackward() },
                    size: 18,
                    buttonSize: Metrics.transportButtonSize
                )

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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
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

    // MARK: - Clock

    private let timerPresets = [1, 5, 10, 15, 25, 30]

    private var clockTint: Color {
        DesignTokens.Color.timerAccent
    }

    private func startClock() {
        switch activity.clockMode {
        case .timer: activity.startTimer()
        case .stopwatch: activity.startStopwatch()
        }
    }

    /// Timer, Stopwatch and Pomodoro side by side in one segmented
    /// control; the highlight slides between them.
    private var clockSegments: some View {

        HStack(spacing: 2) {

            ForEach(LauncherActivity.ClockMode.allCases) { mode in

                Button {
                    withAnimation(.smooth(duration: 0.28)) {
                        activity.clockMode = mode
                    }
                } label: {
                    Text(mode.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(
                            activity.clockMode == mode
                                ? DesignTokens.Color.primaryText
                                : DesignTokens.Color.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background {
                            if activity.clockMode == mode {
                                Capsule()
                                    .fill(Color.white.opacity(0.18))
                                    .matchedGeometryEffect(id: "segment", in: clockSegmentSpace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(DesignTokens.Color.deviceIconBackground))
    }

    private var clockPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            HStack(spacing: 10) {

                backButton

                clockSegments

                Button(action: startClock) {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .frame(height: Metrics.startButtonHeight)
                        .background(Capsule().fill(clockTint))
                }
                .buttonStyle(LauncherPressStyle())
            }

            Group {
                switch activity.clockMode {

                case .timer:
                    VStack(spacing: Metrics.sectionSpacing) {

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

                case .stopwatch:
                    VStack(spacing: 8) {

                        Spacer(minLength: 0)

                        Image(systemName: "stopwatch")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(DesignTokens.Color.timerAccent)

                        Text("Counts up from zero and stays in the notch")
                            .font(Metrics.subtitleFont)
                            .foregroundStyle(DesignTokens.Color.secondaryText)

                        Spacer(minLength: 0)
                    }

                }
            }
            .id(activity.clockMode)
            .transition(.opacity)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(.smooth(duration: 0.28), value: activity.clockMode)
    }

    // MARK: - Pomodoro

    private var pomodoroPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            HStack(spacing: 10) {

                backButton

                Text("Pomodoro")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)

                Button {
                    activity.startPomodoro()
                } label: {
                    Text("Start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 18)
                        .frame(height: Metrics.startButtonHeight)
                        .background(Capsule().fill(DesignTokens.Color.pomodoroAccent))
                }
                .buttonStyle(LauncherPressStyle())
            }

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

    // MARK: - Tools

    private var toolsPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            HStack(spacing: 10) {
                backButton

                Text("Tools")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)
            }

            Grid(horizontalSpacing: Metrics.tileSpacing, verticalSpacing: Metrics.tileSpacing) {

                GridRow {

                    toolTile(symbol: "camera.fill", title: "Camera", subtitle: "Mirror", tint: Color(red: 0.35, green: 0.78, blue: 0.98)) {
                        activity.page = .camera
                    }

                    toolTile(symbol: "waveform.path.ecg", title: "Activity", subtitle: "System", tint: DesignTokens.Color.chargingAccent) {
                        activity.page = .activity
                    }

                    toolTile(symbol: "text.alignleft", title: "Teleprompter", subtitle: "Scrolling script", tint: Color(red: 1, green: 0.62, blue: 0.04)) {
                        activity.page = .teleprompter
                    }
                }

                GridRow {

                    toolTile(symbol: "keyboard", title: "Clean Keyboard", subtitle: "Locks keys 90 s", tint: Color(red: 0.69, green: 0.32, blue: 0.87)) {
                        activity.cleanKeyboard()
                    }

                    toolTile(
                        symbol: "cup.and.saucer.fill",
                        title: "Keep Awake",
                        subtitle: keepAwake.isOn ? "On" : "Off",
                        tint: Color(red: 1, green: 0.62, blue: 0.04),
                        isOn: keepAwake.isOn
                    ) {
                        withAnimation(.smooth(duration: 0.25)) { keepAwake.toggle() }
                    }

                    Color.clear.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private func toolTile(
        symbol: String,
        title: String,
        subtitle: String,
        tint: Color,
        isOn: Bool = false,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {

            VStack(spacing: 6) {

                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isOn ? Color.black : tint)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isOn ? tint : tint.opacity(0.16)))

                VStack(spacing: 1) {

                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(subtitle)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Metrics.tileCornerRadius, style: .continuous)
                    .fill(DesignTokens.Color.deviceIconBackground)
            )
        }
        .buttonStyle(LauncherPressStyle())
    }

    // MARK: - Camera

    private var cameraPage: some View {

        VStack(spacing: Metrics.sectionSpacing - 4) {

            HStack(spacing: 10) {

                Button {
                    activity.page = .tools
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                        .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
                }
                .buttonStyle(LauncherPressStyle())
                .accessibilityLabel("Back")

                Text("Camera")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)
            }

            ZStack {

                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))

                switch camera.access {

                case .allowed:
                    CameraPreviewView(session: camera.session)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(alignment: .bottomTrailing) {
                            blurToggle
                        }

                case .denied:
                    VStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                        Text("Camera access is off for ARC")
                            .font(Metrics.subtitleFont)
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                        Button("Open Privacy Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.link)
                        .font(.system(size: 12, weight: .semibold))
                    }

                case .checking:
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    /// Opens macOS's Video Effects, where Background blur is switched on.
    /// Shows whether it currently is.
    private var blurToggle: some View {

        Button {
            camera.openVideoEffects()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.and.background.dotted")
                    .font(.system(size: 12, weight: .medium))
                Text(camera.isBlurOn ? "Blur on" : "Blur")
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(camera.isBlurOn ? Color.black : DesignTokens.Color.primaryText)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background(
                Capsule().fill(camera.isBlurOn ? Color.white : Color.black.opacity(0.55))
            )
        }
        .buttonStyle(LauncherPressStyle())
        .padding(10)
        .help("Opens macOS Video Effects, where you turn Background blur on or off")
        .accessibilityLabel("Background blur")
    }

    // MARK: - Teleprompter

    private var teleprompterPage: some View {

        VStack(spacing: Metrics.sectionSpacing - 4) {

            HStack(spacing: 10) {

                Button {
                    teleRunning = false
                    activity.page = .tools
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                        .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
                }
                .buttonStyle(LauncherPressStyle())
                .accessibilityLabel("Back")

                Text("Teleprompter")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)

                if teleRunning {

                    teleButton(telePaused ? "play.fill" : "pause.fill") { telePaused.toggle() }
                    teleButton("gobackward.10") { teleOffset = max(-60, teleOffset - 120) }
                    teleButton("stop.fill") { teleRunning = false }

                } else {

                    Button {
                        teleOffset = -70
                        telePaused = false
                        teleRunning = !teleScript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    } label: {
                        Text("Start")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 18)
                            .frame(height: Metrics.startButtonHeight)
                            .background(Capsule().fill(Color(red: 1, green: 0.62, blue: 0.04)))
                    }
                    .buttonStyle(LauncherPressStyle())
                }
            }

            if teleRunning {

                // The script, scrolling up at your pace. Tap to pause.
                GeometryReader { proxy in

                    Text(teleScript)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .frame(width: proxy.size.width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .background(
                            GeometryReader { text in
                                Color.clear
                                    .onAppear { teleTextHeight = text.size.height }
                                    .onChange(of: text.size.height) { _, height in teleTextHeight = height }
                            }
                        )
                        .offset(y: -teleOffset)
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
                        .clipped()
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.12),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .clear, location: 1)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { telePaused.toggle() }
                }
                .frame(maxHeight: .infinity)
                .task(id: teleRunning && !telePaused) {

                    guard teleRunning, !telePaused else { return }

                    var last = Date()

                    while !Task.isCancelled {

                        try? await Task.sleep(nanoseconds: 16_000_000)

                        let now = Date()
                        teleOffset += CGFloat(teleSpeed * now.timeIntervalSince(last))
                        last = now

                        if teleOffset > teleTextHeight + 40 {
                            teleRunning = false
                            break
                        }
                    }
                }

            } else {

                ZStack(alignment: .topLeading) {

                    if teleScript.isEmpty {
                        Text("Paste or type your script…")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $teleScript)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .scrollContentBackground(.hidden)
                        .scrollIndicators(.never)
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 8) {

                    Image(systemName: "tortoise.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Color.secondaryText)

                    Slider(value: $teleSpeed, in: 14...90)
                        .controlSize(.small)

                    Image(systemName: "hare.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: teleRunning)
        .onAppear {
            // Needs the keyboard to type a script.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.windows
                    .first { $0 is IslandWindow && $0.isVisible }?
                    .makeKey()
            }
        }
        .onDisappear { teleRunning = false }
    }

    private func teleButton(_ symbol: String, action: @escaping () -> Void) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
                .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
        }
        .buttonStyle(LauncherPressStyle())
    }

    // MARK: - Activity

    private var activityPage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            HStack(spacing: 10) {

                Button {
                    activity.page = .tools
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                        .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
                }
                .buttonStyle(LauncherPressStyle())
                .accessibilityLabel("Back")

                Text("Activity")
                    .font(Metrics.titleFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)

                Spacer(minLength: 0)
            }

            HStack(spacing: Metrics.tileSpacing) {

                gauge("CPU", value: stats.cpu, tint: DesignTokens.Color.chargingAccent)
                gauge("Memory", value: stats.memory, tint: Color(red: 1, green: 0.62, blue: 0.04))
                gauge("Disk", value: stats.disk, tint: Color(red: 0.35, green: 0.78, blue: 0.98))

                VStack(spacing: 6) {

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 4) {
                        rateLine("arrow.down", stats.downloadRate)
                        rateLine("arrow.up", stats.uploadRate)
                    }

                    Text("Network")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.secondaryText)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: Metrics.tileCornerRadius, style: .continuous)
                        .fill(DesignTokens.Color.deviceIconBackground)
                )
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear { stats.start() }
        .onDisappear { stats.stop() }
    }

    private func gauge(_ title: String, value: Double, tint: Color) -> some View {

        VStack(spacing: 8) {

            Spacer(minLength: 0)

            ZStack {

                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 4.5)

                Circle()
                    .trim(from: 0, to: max(0.01, min(1, value)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.smooth(duration: 0.6), value: value)

                Text("\(Int((value * 100).rounded()))")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .contentTransition(.numericText())
            }
            .frame(width: 52, height: 52)

            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Metrics.tileCornerRadius, style: .continuous)
                .fill(DesignTokens.Color.deviceIconBackground)
        )
    }

    private func rateLine(_ symbol: String, _ bytesPerSecond: Double) -> some View {

        HStack(spacing: 4) {

            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.Color.secondaryText)

            Text(Self.rate(bytesPerSecond))
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private static func rate(_ bytesPerSecond: Double) -> String {

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]

        return formatter.string(fromByteCount: Int64(bytesPerSecond)) + "/s"
    }

    // MARK: - Clipboard

    private var filteredEntries: [ClipboardEntry] {

        let query = clipboardQuery.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else { return clipboard.entries }

        return clipboard.entries.filter {
            $0.searchText.localizedCaseInsensitiveContains(query)
        }
    }

    private var clipboardPage: some View {

        VStack(spacing: Metrics.sectionSpacing - 4) {

            HStack(spacing: 10) {

                backButton

                searchField

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

            if filteredEntries.isEmpty {

                Spacer(minLength: 0)

                Text(
                    !clipboard.entries.isEmpty
                        ? "Nothing matches “\(clipboardQuery)”"
                        : AppSettings.keepClipboardHistory
                            ? "Things you copy will show up here"
                            : "Clipboard history is turned off in Settings"
                )
                .font(Metrics.subtitleFont)
                .foregroundStyle(DesignTokens.Color.secondaryText)

                Spacer(minLength: 0)

            } else {

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(filteredEntries) { entry in
                            clipboardRow(entry)
                        }
                    }
                }
            }
        }
        .onDisappear { clipboardQuery = "" }
    }

    private var backButton: some View {

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
    }

    private var searchField: some View {

        HStack(spacing: 7) {

            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.secondaryText)

            TextField("Search clipboard", text: $clipboardQuery)
                .textFieldStyle(.plain)
                .font(Metrics.subtitleFont)
                .foregroundStyle(DesignTokens.Color.primaryText)

            if !clipboardQuery.isEmpty {
                Button {
                    clipboardQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Metrics.controlSize)
        .background(Capsule().fill(DesignTokens.Color.deviceIconBackground))
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

                if case .image(let data) = entry.content {
                    ClipboardThumbnail(data: data)
                } else {
                    Image(systemName: entry.symbolName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DesignTokens.Color.capsLockAccent)
                        .frame(width: 28)
                }

                Text(entry.preview)
                    .font(Metrics.tileFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if copiedID == entry.id {
                    Label("Copied", systemImage: "checkmark")
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.chargingAccent)
                        .transition(.opacity)
                } else {
                    Button {
                        clipboard.remove(entry)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove")
                }
            }
            .animation(AnimationTokens.stateUpdate, value: copiedID)
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
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

    // MARK: - Notes

    private var notesPage: some View {

        VStack(spacing: 6) {

            HStack(spacing: 8) {

                backButton

                Spacer(minLength: 0)

                boardButton(
                    "clock",
                    label: "History",
                    tint: showNoteHistory ? NoteActivity.accent : DesignTokens.Color.primaryText
                ) {
                    showNoteHistory.toggle()
                }

                boardButton(
                    notes.editing?.isPinned == true ? "pin.fill" : "pin",
                    label: notes.editing?.isPinned == true ? "Unpin" : "Pin to notch",
                    tint: notes.editing?.isPinned == true ? NoteActivity.accent : DesignTokens.Color.primaryText
                ) {
                    notes.pinEditing()
                }
                .disabled(notes.editing == nil)
            }

            noteTabs

            ZStack {

                // The board itself: the whole card is the page.
                ZStack(alignment: .topLeading) {

                    if notes.draft.isEmpty {
                        Text("Write something…")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: Binding(
                        get: { notes.draft },
                        set: { notes.draft = $0 }
                    ))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .focused($noteFocused)
                }
                .opacity(showNoteHistory ? 0 : 1)

                if showNoteHistory {
                    noteHistory
                        .transition(.opacity)
                }
            }
            .frame(maxHeight: .infinity)

            // A quiet status line, like a document's.
            HStack {

                if let note = notes.editing {
                    Text(note.isPinned ? "Pinned to notch" : "Not pinned")
                    Spacer()
                    Text("Saved \(note.date.formatted(.relative(presentation: .named)))")
                } else {
                    Text("Starts saving as you type")
                    Spacer()
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignTokens.Color.secondaryText.opacity(0.8))
            .lineLimit(1)
        }
        .animation(AnimationTokens.stateUpdate, value: showNoteHistory)
        .onAppear {
            notes.openBoard()
            showNoteHistory = false
            // Straight into typing: the island's panel takes the keyboard
            // (without bringing ARC to the front) and the board focuses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                NSApp.windows
                    .first { $0 is IslandWindow && $0.isVisible }?
                    .makeKey()
                noteFocused = true
            }
        }
    }

    /// Open notes as tabs, Safari-style: tap to switch, ✕ on the one you're
    /// in to close it, + for a fresh one.
    private var noteTabs: some View {

        ScrollView(.horizontal, showsIndicators: false) {

            HStack(spacing: 6) {

                ForEach(notes.notes.prefix(5)) { note in
                    noteTab(
                        title: Self.tabTitle(note.text),
                        isSelected: notes.editingID == note.id,
                        onSelect: {
                            withAnimation(.smooth(duration: 0.25)) {
                                notes.editingID = note.id
                                showNoteHistory = false
                            }
                            noteFocused = true
                        },
                        onClose: { withAnimation(.smooth(duration: 0.25)) { notes.delete(note.id) } }
                    )
                }

                // A blank board is its own tab until you type.
                if notes.editing == nil {
                    noteTab(title: "New note", isSelected: true, onSelect: {}, onClose: nil)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                Button {
                    withAnimation(.smooth(duration: 0.25)) {
                        notes.startNewNote()
                        showNoteHistory = false
                    }
                    noteFocused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                        .frame(width: 26, height: 26)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New note")
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 28)
        .animation(.smooth(duration: 0.25), value: notes.notes.count)
    }

    private func noteTab(
        title: String,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onClose: (() -> Void)?
    ) -> some View {

        HStack(spacing: 4) {

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: 96)

            if isSelected, let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close tab")
            }
        }
        .foregroundStyle(isSelected ? DesignTokens.Color.primaryText : DesignTokens.Color.secondaryText)
        .padding(.horizontal, 11)
        .frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(isSelected ? 0.16 : 0.07)))
        .contentShape(Capsule())
        .onTapGesture(perform: onSelect)
    }

    private static func tabTitle(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Every saved note, newest first — tap one to open it on the board.
    private var noteHistory: some View {

        VStack(spacing: 6) {

            if notes.notes.isEmpty {

                Spacer(minLength: 0)

                Text("No notes yet")
                    .font(Metrics.subtitleFont)
                    .foregroundStyle(DesignTokens.Color.secondaryText)

                Spacer(minLength: 0)

            } else {

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(notes.notes) { note in
                            noteRow(note)
                        }
                    }
                }

                Button {
                    notes.clearAll()
                    showNoteHistory = false
                } label: {
                    Text("Clear history")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func boardButton(
        _ symbol: String,
        label: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: Metrics.controlSize, height: Metrics.controlSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(LauncherPressStyle())
        .accessibilityLabel(label)
    }

    private func noteRow(_ note: QuickNote) -> some View {

        HStack(spacing: 10) {

            Button {
                notes.editingID = note.id
                showNoteHistory = false
                noteFocused = true
            } label: {
                Text(note.text)
                    .font(Metrics.tileFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if note.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(NoteActivity.accent)
            }

            Button {
                notes.delete(note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .frame(width: 20, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete")
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignTokens.Color.deviceIconBackground)
        )
    }

    // MARK: - Setup components

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
    }
}

/// A small preview of a copied image, decoded off the main thread and at
/// thumbnail size so a big screenshot doesn't slow the list.
private struct ClipboardThumbnail: View {

    let data: Data

    @State private var image: NSImage?

    var body: some View {

        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.clear
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task {
            image = await Task.detached(priority: .utility) { () -> NSImage? in
                guard
                    let source = CGImageSourceCreateWithData(data as CFData, nil),
                    let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 64
                    ] as CFDictionary)
                else { return nil }
                return NSImage(cgImage: cg, size: NSSize(width: 28, height: 28))
            }.value
        }
    }
}

/// A running clock on the launcher's home page, the way what's playing
/// is: its glyph, the time, and pause / stop.
private struct LauncherTimerRow: View {

    @ObservedObject var slot: TimerSlot

    private typealias Metrics = DesignTokens.LauncherMetrics

    var body: some View {

        HStack(spacing: 8) {

            Image(systemName: slot.glyph)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(slot.accent)
                .frame(width: 20)

            Text(slot.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .lineLimit(1)

            Text(TimerIslandView.format(slot.displaySeconds))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Color.primaryText)
                .opacity(slot.phase == .paused ? 0.55 : 1)
                .contentTransition(.numericText(countsDown: slot.countsDown))

            Spacer(minLength: 6)

            if slot.phase != .finished {
                button(slot.phase == .paused ? "play.fill" : "pause.fill", tint: slot.accent) {
                    withAnimation(.easeInOut(duration: 0.22)) { slot.togglePause() }
                }
            }

            button("xmark", tint: DesignTokens.Color.primaryText) {
                withAnimation(.easeInOut(duration: 0.3)) { slot.cancel() }
            }
        }
        .animation(.easeInOut(duration: 0.22), value: slot.phase)
        .padding(.horizontal, 12)
        .frame(height: Metrics.timerRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Metrics.tileCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .transition(.opacity)
    }

    private func button(_ symbol: String, tint: Color, action: @escaping () -> Void) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .background(Circle().fill(DesignTokens.Color.deviceIconBackground))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "xmark" ? "Stop" : "Pause or resume")
    }
}

