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
        .animation(.easeInOut(duration: 0.28), value: panelSize)
        .animation(.easeInOut(duration: 0.2), value: bluetooth.connected.isEmpty)
    }

    // MARK: - Home

    private var homePage: some View {

        VStack(spacing: Metrics.sectionSpacing) {

            nowPlayingRow

            ForEach(Array(timer.activeSlots.prefix(2)), id: \.kind) { slot in
                LauncherTimerRow(slot: slot)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

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

                tile(
                    symbol: "note.text",
                    title: "Notes",
                    tint: NoteActivity.accent
                ) {
                    activity.page = .notes
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
                    "square.and.pencil",
                    label: "New note",
                    tint: DesignTokens.Color.primaryText
                ) {
                    notes.startNewNote()
                    showNoteHistory = false
                    noteFocused = true
                }

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
