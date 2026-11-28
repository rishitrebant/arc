import SwiftUI

// The tab contents below are hosted by `SettingsWindowController` (one
// `NSHostingController` per tab inside an `NSTabViewController` with the
// toolbar tab style), not by a SwiftUI `Settings` scene — macOS 14+
// blocks opening that scene from AppKit code.
//
// Every tab is a native grouped `Form` (the System Settings look) inside
// a window of one fixed size, so a long tab scrolls instead of growing
// the window past the screen.

// MARK: - Shared building blocks

/// A row's title with a quiet explanation beneath it.
private struct SettingLabel: View {

    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A toggle with a title and an explanation.
private struct SettingToggle: View {

    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            SettingLabel(title: title, detail: detail)
        }
    }
}

/// The page every tab sits on.
private struct SettingsPage<Content: View>: View {

    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.grouped)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {

    @State private var launchAtLogin = AppSettings.launchAtLoginEnabled
    @AppStorage(AppSettings.Key.alwaysShowMenuBarIcon)
    private var alwaysShowIcon = AppSettings.Default.alwaysShowMenuBarIcon
    @AppStorage(AppSettings.Key.hapticsEnabled)
    private var haptics = AppSettings.Default.hapticsEnabled
    @AppStorage(AppSettings.Key.showDockIcon)
    private var showDockIcon = AppSettings.Default.showDockIcon
    @AppStorage(AppSettings.Key.globalShortcutsEnabled)
    private var shortcuts = AppSettings.Default.globalShortcutsEnabled

    var body: some View {
        SettingsPage {

            Section("Startup") {

                SettingToggle(
                    title: "Launch ARC at login",
                    isOn: $launchAtLogin
                )
                .onChange(of: launchAtLogin) { _, wanted in
                    let applied = AppSettings.setLaunchAtLogin(wanted)
                    if !applied { launchAtLogin = AppSettings.launchAtLoginEnabled }
                }
            }

            Section("Dock") {

                SettingToggle(
                    title: "Show ARC in the Dock",
                    detail: "Turn this off and ARC keeps running from the menu bar, with no Dock icon. Open these settings from the menu bar icon.",
                    isOn: $showDockIcon
                )
            }

            Section("Menu bar") {

                SettingToggle(
                    title: "Always show the menu bar icon",
                    detail: "By default the icon only appears while an external display is connected. If it's hidden, opening ARC again from the Dock, Spotlight or Finder brings up these settings.",
                    isOn: $alwaysShowIcon
                )
                .onChange(of: alwaysShowIcon) { _, _ in
                    NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
                }
            }

            Section("Feedback and shortcuts") {

                SettingToggle(
                    title: "Haptic feedback",
                    detail: "A subtle trackpad tap when the island opens, a new activity appears, or you press a button.",
                    isOn: $haptics
                )

                SettingToggle(
                    title: "Global keyboard shortcuts",
                    detail: "⌃⌥Space opens the launcher  ·  ⌃⌥T starts your last timer  ·  ⌃⌥S starts or stops the stopwatch  ·  ⌃⌥P starts a pomodoro  ·  ⌥V opens the clipboard  ·  ⌃⌥N writes a note  ·  ⌃⌥U pins or unpins one.",
                    isOn: $shortcuts
                )
            }
        }
    }
}

// MARK: - Launcher

struct LauncherSettingsTab: View {

    @AppStorage(AppSettings.Key.launcherOpensOnHover)
    private var launcherOnHover = AppSettings.Default.launcherOpensOnHover
    @AppStorage(AppSettings.Key.launcherTrigger)
    private var launcherTrigger = AppSettings.Default.launcherTrigger
    @AppStorage(AppSettings.Key.activityOwnsHover)
    private var activityOwnsHover = AppSettings.Default.activityOwnsHover
    @AppStorage(AppSettings.Key.openClipboardOnPaste)
    private var clipboardOnPaste = AppSettings.Default.openClipboardOnPaste
    @AppStorage(AppSettings.Key.showScreenTime)
    private var screenTime = AppSettings.Default.showScreenTime
    @AppStorage(AppSettings.Key.launcherBatteryWidget)
    private var launcherBattery = AppSettings.Default.launcherBatteryWidget
    @ObservedObject private var notes = NoteStore.shared
    @State private var confirmClearNotes = false

    var body: some View {
        SettingsPage {

            Section("Opening") {

                Picker(selection: $launcherTrigger) {
                    ForEach(LauncherTrigger.allCases, id: \.rawValue) { trigger in
                        Text(trigger.title).tag(trigger.rawValue)
                    }
                } label: {
                    SettingLabel(
                        title: "Open the launcher by",
                        detail: "Click the notch, or only the very top edge of the screen near the center — so a click on the notch never opens it by accident. Off turns the launcher menu off completely, including ⌃⌥Space."
                    )
                }

                SettingToggle(
                    title: "Open the launcher when I hover over the notch",
                    detail: "Rest the cursor on the notch (or the top edge, if that's selected above) and the launcher opens by itself — no click.",
                    isOn: $launcherOnHover
                )
                .disabled(launcherTrigger == LauncherTrigger.off.rawValue)

                SettingToggle(
                    title: "Hover opens what's playing; click opens the launcher",
                    detail: "While music, a timer or anything else is on the island, resting the cursor on it opens that card, and only a click on the notch opens the launcher. Off lets the notch hover open the launcher even then.",
                    isOn: $activityOwnsHover
                )

                SettingToggle(
                    title: "Open the clipboard when I paste",
                    detail: "Pressing ⌘V also opens the clipboard in the launcher. macOS asks for Input Monitoring permission the first time — ARC only watches for ⌘V, and you may need to reopen ARC after allowing it. ⌥V opens the clipboard without it.",
                    isOn: $clipboardOnPaste
                )
                .disabled(launcherTrigger == LauncherTrigger.off.rawValue)

                if clipboardOnPaste, !PasteMonitor.hasAccess {

                    HStack {

                        Text("ARC doesn't have Input Monitoring access yet, so ⌘V can't be seen.")
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button("Open Settings…") {
                            NSWorkspace.shared.open(
                                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
                            )
                        }
                    }
                }

            }

            Section("Home page") {

                SettingToggle(
                    title: "Show active time",
                    detail: "How long you've been at the Mac today, counted by ARC while it runs. macOS gives apps no Screen Time data, so this is ARC's own count, kept on this Mac.",
                    isOn: $screenTime
                )

                Picker(selection: $launcherBattery) {
                    ForEach(LauncherBatteryWidget.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                } label: {
                    SettingLabel(
                        title: "Battery rings",
                        detail: "This Mac and your connected devices, as small rings. Off shows the connected device on its own row instead."
                    )
                }
            }

            Section("Notes") {

                HStack {
                    SettingLabel(
                        title: "Saved notes",
                        detail: "\(notes.notes.count) on this Mac. Notes live only in ARC's own storage."
                    )
                    Spacer()
                    Button("Clear All…", role: .destructive) { confirmClearNotes = true }
                        .disabled(notes.notes.isEmpty)
                }
                .confirmationDialog(
                    "Delete all notes?",
                    isPresented: $confirmClearNotes
                ) {
                    Button("Delete All Notes", role: .destructive) { notes.clearAll() }
                } message: {
                    Text("This also unpins the note in the notch. It can't be undone.")
                }
            }

        }
    }
}

// MARK: - Display

struct DisplaySettingsTab: View {

    @State private var mode = NotchDisplayMode.current
    @AppStorage(AppSettings.Key.expandedTopCorners)
    private var topCorners = AppSettings.Default.expandedTopCorners
    @AppStorage(AppSettings.Key.cornerRoundness)
    private var roundness = AppSettings.Default.cornerRoundness
    @AppStorage(AppSettings.Key.bounceAmount)
    private var bounce = AppSettings.Default.bounceAmount
    @AppStorage(AppSettings.Key.notchGlowEnabled)
    private var glowEnabled = AppSettings.Default.notchGlowEnabled
    @AppStorage(AppSettings.Key.notchGlowColor)
    private var glowColor = AppSettings.Default.notchGlowColor
    @AppStorage(AppSettings.Key.notchGlowIntensity)
    private var glowIntensity = AppSettings.Default.notchGlowIntensity
    @AppStorage(AppSettings.Key.notchGlowOnHover)
    private var glowOnHover = AppSettings.Default.notchGlowOnHover

    var body: some View {
        SettingsPage {

            Section("Screens") {

                Picker(selection: $mode) {
                    ForEach(NotchDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.menuTitle).tag(mode)
                    }
                } label: {
                    SettingLabel(
                        title: "Show ARC on",
                        detail: "The built-in display is the default. External monitors have no real notch, so ARC draws one there when you opt in."
                    )
                }
                .onChange(of: mode) { _, newValue in
                    NotchDisplayMode.current = newValue
                    NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
                }
            }

            Section("Appearance") {

                Picker(selection: $topCorners) {
                    ForEach(ExpandedTopCorners.allCases, id: \.rawValue) { corners in
                        Text(corners.title).tag(corners.rawValue)
                    }
                } label: {
                    SettingLabel(
                        title: "Expanded top corners",
                        detail: "Rounded keeps the open island a floating card. Blended makes its top edge flat and sweeps it into the top of the screen, the way the compact pill meets the notch. Applies the next time the island opens."
                    )
                }
            }

            Section("Shape and motion") {

                VStack(alignment: .leading, spacing: 6) {
                    SettingLabel(
                        title: "Corner roundness",
                        detail: "How round the island's corners are, from nearly square to very round."
                    )
                    HStack {
                        Text("Sharp").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $roundness, in: 0.3...1.4)
                        Text("Round").font(.caption).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    SettingLabel(
                        title: "Bounce",
                        detail: "How much the island overshoots and settles when it opens. Zero is a smooth glide."
                    )
                    HStack {
                        Text("None").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $bounce, in: 0...0.5)
                        Text("Lots").font(.caption).foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Reset") {
                        roundness = AppSettings.Default.cornerRoundness
                        bounce = AppSettings.Default.bounceAmount
                    }
                }
            }

            Section("Notch glow") {

                SettingToggle(
                    title: "Glow around the notch",
                    detail: "A soft glow around the notch while nothing else is on the island.",
                    isOn: $glowEnabled
                )

                SettingToggle(
                    title: "Glow when I hover over the notch",
                    detail: "The notch lights up while the cursor is on it, even with the glow above turned off.",
                    isOn: $glowOnHover
                )

                Picker("Glow colour", selection: $glowColor) {
                    ForEach(NotchGlowColor.allCases, id: \.rawValue) { option in
                        Text(option.title).tag(option.rawValue)
                    }
                }
                .disabled(!glowEnabled && !glowOnHover)

                Slider(value: $glowIntensity, in: 0.2...2) {
                    Text("Glow intensity")
                }
                .disabled(!glowEnabled && !glowOnHover)
            }
        }
    }
}

// MARK: - Media

struct MediaSettingsTab: View {

    @AppStorage(AppSettings.Key.musicLingerSeconds)
    private var lingerSeconds = AppSettings.Default.musicLingerSeconds

    @AppStorage(AppSettings.Key.nextUpEnabled)
    private var nextUp = AppSettings.Default.nextUpEnabled

    @AppStorage(AppSettings.Key.youtubeControlsEnabled)
    private var youtubeEnabled = AppSettings.Default.youtubeControlsEnabled
    @AppStorage(AppSettings.Key.youtubeCompactIcon)
    private var compactIcon = AppSettings.Default.youtubeCompactIcon
    @AppStorage(AppSettings.Key.youtubeDetection)
    private var detection = AppSettings.Default.youtubeDetection

    private let lingerOptions: [(String, Double)] = [
        ("5 seconds", 5), ("10 seconds", 10), ("20 seconds", 20),
        ("30 seconds", 30), ("1 minute", 60)
    ]

    var body: some View {
        SettingsPage {

            Section("Music") {

                Picker(selection: $lingerSeconds) {
                    ForEach(lingerOptions, id: \.1) { Text($0.0).tag($0.1) }
                } label: {
                    SettingLabel(
                        title: "Stay after pausing",
                        detail: "How long the island stays up after playback pauses. It never closes while your cursor is on it. Also applies to YouTube."
                    )
                }

                SettingToggle(
                    title: "Show what's next",
                    detail: "A small card with the next song as one is about to end, with a button to skip to it. Works with Apple Music playlists (not when shuffled); Spotify doesn't share its queue.",
                    isOn: $nextUp
                )
            }

            Section("YouTube") {

                SettingToggle(
                    title: "Show YouTube controls",
                    detail: "A video playing in your browser gets the same island as Music: thumbnail, title, progress, and back 5 seconds, play / pause, forward 5 seconds.",
                    isOn: $youtubeEnabled
                )

                Picker(selection: $compactIcon) {
                    ForEach(YouTubeCompactIcon.allCases, id: \.rawValue) { icon in
                        Text(icon.title).tag(icon.rawValue)
                    }
                } label: {
                    SettingLabel(
                        title: "Compact pill shows",
                        detail: "What sits on the left of the pill while a video plays."
                    )
                }
                .disabled(!youtubeEnabled)

                Picker(selection: $detection) {
                    ForEach(YouTubeDetection.allCases, id: \.rawValue) { choice in
                        Text(choice.title).tag(choice.rawValue)
                    }
                } label: {
                    SettingLabel(
                        title: "Take over",
                        detail: "“YouTube only” checks your browser's tabs to confirm the video is on YouTube (macOS asks for Automation access to that browser). A browser that can't be checked, such as Firefox, is shown anyway."
                    )
                }
                .disabled(!youtubeEnabled)
            }
        }
    }
}

// MARK: - Timers

/// The quick-start durations shared by the menu bar and the Timers tab.
enum TimerPreset {

    static let all: [(title: String, seconds: TimeInterval)] = [
        ("1 minute", 60), ("5 minutes", 300), ("10 minutes", 600),
        ("15 minutes", 900), ("25 minutes", 1500), ("30 minutes", 1800),
        ("1 hour", 3600)
    ]

    /// `nil` starts a stopwatch. `TimerActivity` listens for this.
    static func start(_ seconds: TimeInterval?) {
        NotificationCenter.default.post(
            name: .islandStartTimer,
            object: nil,
            userInfo: seconds.map { ["kind": "countdown", "duration": $0] }
                ?? ["kind": "stopwatch"]
        )
    }

    static func startPomodoro(focus: TimeInterval, rest: TimeInterval) {
        NotificationCenter.default.post(
            name: .islandStartTimer,
            object: nil,
            userInfo: ["kind": "pomodoro", "duration": focus, "breakDuration": rest]
        )
    }
}

struct TimerSettingsTab: View {

    @AppStorage(AppSettings.Key.focusSound)
    private var focusSound = AppSettings.Default.focusSound
    @AppStorage(AppSettings.Key.focusSoundVolume)
    private var focusVolume = AppSettings.Default.focusSoundVolume

    @State private var customMinutes = 10
    @State private var focusMinutes = 25
    @State private var breakMinutes = 5

    var body: some View {
        SettingsPage {

            Section("Timer") {

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(TimerPreset.all, id: \.seconds) { preset in
                        Button(preset.title) { TimerPreset.start(preset.seconds) }
                            .frame(maxWidth: .infinity)
                    }
                }

                HStack(spacing: 8) {
                    Text("Custom")
                    Spacer()
                    TextField("", value: $customMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $customMinutes, in: 1...999)
                        .labelsHidden()
                    Text("min").foregroundStyle(.secondary)
                        .onChange(of: customMinutes) { _, value in
                            customMinutes = min(max(value, 1), 999)
                        }
                    Button("Start") {
                        TimerPreset.start(TimeInterval(min(max(customMinutes, 1), 999) * 60))
                    }
                }
            }

            Section("Pomodoro") {

                HStack(spacing: 8) {
                    Text("Focus")
                    Spacer()
                    TextField("", value: $focusMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $focusMinutes, in: 1...180)
                        .labelsHidden()
                    Text("min").foregroundStyle(.secondary)
                }
                .onChange(of: focusMinutes) { _, value in
                    focusMinutes = min(max(value, 1), 180)
                }

                HStack(spacing: 8) {
                    Text("Break")
                    Spacer()
                    TextField("", value: $breakMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                    Stepper("", value: $breakMinutes, in: 1...60)
                        .labelsHidden()
                    Text("min").foregroundStyle(.secondary)
                }
                .onChange(of: breakMinutes) { _, value in
                    breakMinutes = min(max(value, 1), 60)
                }

                Picker(selection: $focusSound) {
                    ForEach(FocusSound.allCases) { Text($0.title).tag($0.rawValue) }
                } label: {
                    SettingLabel(
                        title: "Focus sound",
                        detail: "Plays softly while a focus session runs, and stops for breaks."
                    )
                }

                if focusSound != FocusSound.off.rawValue {
                    HStack {
                        Text("Volume")
                        Slider(value: $focusVolume, in: 0.05...1)
                    }
                }

                HStack {
                    Spacer()
                    Button("Start Pomodoro") {
                        TimerPreset.startPomodoro(
                            focus: TimeInterval(focusMinutes * 60),
                            rest: TimeInterval(breakMinutes * 60)
                        )
                    }
                }
            }

            Section("Stopwatch") {

                HStack {
                    Text("Count up from zero")
                    Spacer()
                    Button("Start Stopwatch") { TimerPreset.start(nil) }
                }
            }
        }
    }
}

// MARK: - Devices & power

struct DevicesSettingsTab: View {

    @AppStorage(AppSettings.Key.showBluetoothAlert)
    private var showBluetooth = AppSettings.Default.showBluetoothAlert
    @AppStorage(AppSettings.Key.showAudioOutputChanges)
    private var showAudioOutput = AppSettings.Default.showAudioOutputChanges

    @AppStorage(AppSettings.Key.showChargingIndicator)
    private var showCharging = AppSettings.Default.showChargingIndicator
    @AppStorage(AppSettings.Key.showChargerDisconnectedAlert)
    private var showDisconnected = AppSettings.Default.showChargerDisconnectedAlert
    @AppStorage(AppSettings.Key.showLowBatteryAlert)
    private var showLowBattery = AppSettings.Default.showLowBatteryAlert
    @AppStorage(AppSettings.Key.lowBatteryTriggerPercent)
    private var lowBatteryPercent = AppSettings.Default.lowBatteryTriggerPercent

    var body: some View {
        SettingsPage {

            Section("Bluetooth audio") {

                SettingToggle(
                    title: "Show when speakers or headphones connect",
                    detail: "Includes AirPods, with their battery when macOS reports it. Hover over the card to disconnect. Mice and keyboards aren't included.",
                    isOn: $showBluetooth
                )
            }

            Section("Sound output") {

                SettingToggle(
                    title: "Show when the output device changes",
                    detail: "AirPods, AirPlay, a display or the built-in speakers.",
                    isOn: $showAudioOutput
                )
            }

            Section("Charging") {

                SettingToggle(
                    title: "Show when the charger is connected",
                    isOn: $showCharging
                )

                SettingToggle(
                    title: "Show when the charger is disconnected",
                    isOn: $showDisconnected
                )
            }

            Section("Low battery") {

                SettingToggle(
                    title: "Offer Low Power Mode when the battery is low",
                    detail: "Click the alert to turn Low Power Mode on (macOS asks for your password).",
                    isOn: $showLowBattery
                )

                HStack(spacing: 8) {
                    Text("Alert at")
                    Spacer()
                    TextField("", value: $lowBatteryPercent, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .onSubmit { clamp() }
                    Stepper("", value: $lowBatteryPercent, in: AppSettings.lowBatteryTriggerRange)
                        .labelsHidden()
                    Text("%").foregroundStyle(.secondary)
                }
                .disabled(!showLowBattery)
                // Clamp whenever the value changes, so a typed 150 or 0
                // snaps back into range instead of being stored.
                .onChange(of: lowBatteryPercent) { _, _ in clamp() }
            }
        }
    }

    private func clamp() {
        let range = AppSettings.lowBatteryTriggerRange
        let clamped = min(max(lowBatteryPercent, range.lowerBound), range.upperBound)
        if clamped != lowBatteryPercent {
            lowBatteryPercent = clamped
        }
    }
}

// MARK: - Alerts

struct AlertsSettingsTab: View {

    @AppStorage(AppSettings.Key.showCalendarAlerts)
    private var showCalendar = AppSettings.Default.showCalendarAlerts
    @AppStorage(AppSettings.Key.calendarLeadMinutes)
    private var calendarLead = AppSettings.Default.calendarLeadMinutes
    @AppStorage(AppSettings.Key.showPrivacyIndicators)
    private var showPrivacy = AppSettings.Default.showPrivacyIndicators
    @AppStorage(AppSettings.Key.showFocusChanges)
    private var showFocus = AppSettings.Default.showFocusChanges
    @AppStorage(AppSettings.Key.showCapsLockIndicator)
    private var showCapsLock = AppSettings.Default.showCapsLockIndicator
    @AppStorage(AppSettings.Key.showDownloadProgress)
    private var showDownloads = AppSettings.Default.showDownloadProgress
    @AppStorage(AppSettings.Key.waterReminderEnabled)
    private var waterReminder = AppSettings.Default.waterReminderEnabled
    @AppStorage(AppSettings.Key.volumeIndicatorEnabled)
    private var volumeIndicator = AppSettings.Default.volumeIndicatorEnabled

    var body: some View {
        SettingsPage {

            Section("Reminders") {

                SettingToggle(
                    title: "Drink water",
                    detail: "A small reminder in the island every hour. No notification, so nothing to allow.",
                    isOn: $waterReminder
                )
            }

            Section("Calendar") {

                SettingToggle(
                    title: "Show upcoming meetings",
                    detail: "With a Join button when the event has a video link. ARC asks for calendar access the first time.",
                    isOn: $showCalendar
                )

                Picker("Tell me", selection: $calendarLead) {
                    ForEach([1, 5, 10, 15], id: \.self) { minutes in
                        Text("\(minutes) min before").tag(minutes)
                    }
                }
                .disabled(!showCalendar)
            }

            Section("Downloads") {

                SettingToggle(
                    title: "Show download progress",
                    detail: "Safari, Chrome and Firefox downloads to your Downloads folder. ARC asks for Downloads folder access the first time.",
                    isOn: $showDownloads
                )
            }

            Section("System") {

                SettingToggle(
                    title: "Microphone, camera and screen recording",
                    detail: "Briefly shows when one turns on.",
                    isOn: $showPrivacy
                )

                SettingToggle(
                    title: "Focus",
                    detail: "Shows when a Focus turns on or off. macOS only says whether a Focus is on, not which one — and only if \"Focus Status\" is switched on for that Focus in System Settings → Focus.",
                    isOn: $showFocus
                )

                HStack {
                    Spacer()
                    Button("Open Focus Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }

                SettingToggle(
                    title: "Volume",
                    detail: "A small level pill when the volume changes.",
                    isOn: $volumeIndicator
                )

                SettingToggle(
                    title: "Caps Lock",
                    detail: "Shows whether it's on or off each time you press it.",
                    isOn: $showCapsLock
                )
            }
        }
    }
}

// MARK: - Shelf & clipboard

struct ShelfSettingsTab: View {

    @AppStorage(AppSettings.Key.shelfDurationSeconds)
    private var seconds = AppSettings.Default.shelfDurationSeconds
    @AppStorage(AppSettings.Key.keepClipboardHistory)
    private var clipboardHistory = AppSettings.Default.keepClipboardHistory

    private let options: [(String, Double)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120),
        ("5 minutes", 300), ("15 minutes", 900), ("1 hour", 3600)
    ]

    var body: some View {
        SettingsPage {

            Section("File shelf") {

                Picker(selection: $seconds) {
                    ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
                } label: {
                    SettingLabel(
                        title: "Keep files for",
                        detail: "How long a file waits on the shelf before it's put back where it came from. Applies to files dropped after you change this."
                    )
                }
            }

            Section("Clipboard") {

                SettingToggle(
                    title: "Keep clipboard history",
                    detail: "The launcher lists your last few copies so you can copy one again. History stays in memory only, is never saved to disk, and items from password managers are skipped.",
                    isOn: $clipboardHistory
                )
            }
        }
    }
}

// MARK: - About

struct AboutSettingsTab: View {

    @State private var checksAutomatically =
        UpdateController.shared.automaticallyChecksForUpdates

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)

            Text("ARC")
                .font(.title.weight(.semibold))

            Text(version)
                .foregroundStyle(.secondary)

            Text("The notch, extended.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Button("Check for Updates…") {
                UpdateController.shared.checkForUpdates()
            }
            .padding(.top, 8)

            Toggle("Check for updates automatically", isOn: $checksAutomatically)
                .toggleStyle(.checkbox)
                .onChange(of: checksAutomatically) { _, newValue in
                    UpdateController.shared.automaticallyChecksForUpdates = newValue
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
