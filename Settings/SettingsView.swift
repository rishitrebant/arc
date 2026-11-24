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
    @AppStorage(AppSettings.Key.launcherOpensOnHover)
    private var launcherOnHover = AppSettings.Default.launcherOpensOnHover
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

            Section("Interaction") {

                SettingToggle(
                    title: "Open the launcher when I hover over the notch",
                    detail: "Rest the cursor on the notch and the launcher opens by itself — no click. Clicking the notch (or ⌃⌥Space) still works either way.",
                    isOn: $launcherOnHover
                )

                SettingToggle(
                    title: "Haptic feedback",
                    detail: "A subtle trackpad tap when the island opens, a new activity appears, or you press a button.",
                    isOn: $haptics
                )

                SettingToggle(
                    title: "Global keyboard shortcuts",
                    detail: "⌃⌥Space opens the launcher  ·  ⌃⌥T starts your last timer  ·  ⌃⌥S starts or stops the stopwatch  ·  ⌃⌥P starts a pomodoro.",
                    isOn: $shortcuts
                )
            }
        }
    }
}

// MARK: - Display

struct DisplaySettingsTab: View {

    @State private var mode = NotchDisplayMode.current
    @AppStorage(AppSettings.Key.expandedTopCorners)
    private var topCorners = AppSettings.Default.expandedTopCorners

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
        }
    }
}

// MARK: - Media

struct MediaSettingsTab: View {

    @AppStorage(AppSettings.Key.musicLingerSeconds)
    private var lingerSeconds = AppSettings.Default.musicLingerSeconds

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
                    Button("Start") {
                        TimerPreset.start(TimeInterval(min(max(customMinutes, 1), 999) * 60))
                    }
                }
            }

            Section("Pomodoro") {

                Stepper(value: $focusMinutes, in: 1...180) {
                    LabeledContent("Focus", value: "\(focusMinutes) min")
                }

                Stepper(value: $breakMinutes, in: 1...60) {
                    LabeledContent("Break", value: "\(breakMinutes) min")
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

    var body: some View {
        SettingsPage {

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
                    detail: "Shows when a Focus turns on or off. macOS only says whether a Focus is on, not which one.",
                    isOn: $showFocus
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
