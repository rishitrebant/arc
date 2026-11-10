import SwiftUI

// The tab contents below are hosted by `SettingsWindowController` (one
// `NSHostingController` per tab inside an `NSTabViewController` with the
// toolbar tab style), not by a SwiftUI `Settings` scene — macOS 14+
// blocks opening that scene from AppKit code.

// MARK: - Shared layout

/// Label column on the left, controls + grey explainer text on the
/// right — the same shape as the reference screenshot's rows.
private struct SettingsRow<Content: View>: View {

    let title: String
    let detail: String?
    @ViewBuilder let content: Content

    init(
        _ title: String,
        detail: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 150, alignment: .trailing)

            VStack(alignment: .leading, spacing: 6) {
                content
                if let detail {
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TabContainer<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) { content }
            .padding(.vertical, 22)
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - General

struct GeneralSettingsTab: View {

    @State private var launchAtLogin = AppSettings.launchAtLoginEnabled
    @AppStorage(AppSettings.Key.alwaysShowMenuBarIcon)
    private var alwaysShowIcon = AppSettings.Default.alwaysShowMenuBarIcon

    var body: some View {
        TabContainer {
            SettingsRow("Startup:") {
                Toggle("Launch Island at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, wanted in
                        let applied = AppSettings.setLaunchAtLogin(wanted)
                        if !applied { launchAtLogin = AppSettings.launchAtLoginEnabled }
                    }
            }

            SettingsRow(
                "Menu bar icon:",
                detail: "By default the icon only appears while an external display is connected. Turn this on to keep it visible on the MacBook screen too. If the icon is hidden, opening Island again from Spotlight or Finder brings up these settings."
            ) {
                Toggle("Always show menu bar icon", isOn: $alwaysShowIcon)
                    .onChange(of: alwaysShowIcon) { _, _ in
                        NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
                    }
            }
        }
    }
}

// MARK: - Battery

struct BatterySettingsTab: View {

    @AppStorage(AppSettings.Key.showChargingIndicator)
    private var showCharging = AppSettings.Default.showChargingIndicator
    @AppStorage(AppSettings.Key.showLowBatteryAlert)
    private var showLowBattery = AppSettings.Default.showLowBatteryAlert
    @AppStorage(AppSettings.Key.lowBatteryTriggerPercent)
    private var lowBatteryPercent = AppSettings.Default.lowBatteryTriggerPercent

    var body: some View {
        TabContainer {
            SettingsRow(
                "Charging:",
                detail: "Briefly shows the battery level in the notch when you plug in your charger."
            ) {
                Toggle("Show when charger is connected", isOn: $showCharging)
            }

            SettingsRow(
                "Low battery:",
                detail: "When the battery drops low on battery power, shows an alert in the notch. Click it to turn on Low Power Mode (macOS will ask for your password)."
            ) {
                Toggle("Offer Low Power Mode when battery is low", isOn: $showLowBattery)
            }

            SettingsRow(
                "Alert at:",
                detail: "Type any battery level from \(AppSettings.lowBatteryTriggerRange.lowerBound) to \(AppSettings.lowBatteryTriggerRange.upperBound)%, or use the arrows. The alert appears when the battery drops to this level."
            ) {
                HStack(spacing: 6) {
                    TextField("", value: $lowBatteryPercent, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 56)
                        .onSubmit { clamp() }

                    Stepper(
                        "",
                        value: $lowBatteryPercent,
                        in: AppSettings.lowBatteryTriggerRange
                    )
                    .labelsHidden()

                    Text("%")
                        .foregroundStyle(.secondary)
                }
                .disabled(!showLowBattery)
                // Also clamp whenever the value changes, so a typed 150
                // or 0 snaps back into range instead of being stored.
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

// MARK: - Display

struct DisplaySettingsTab: View {

    @State private var mode = NotchDisplayMode.current

    var body: some View {
        TabContainer {
            SettingsRow(
                "Show Island on:",
                detail: "The built-in display is the default. External monitors have no real notch, so Island draws one there when you opt in."
            ) {
                Picker("", selection: $mode) {
                    ForEach(NotchDisplayMode.allCases, id: \.self) { mode in
                        Text(mode.menuTitle).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .onChange(of: mode) { _, newValue in
                    NotchDisplayMode.current = newValue
                    NotificationCenter.default.post(name: AppSettings.didChange, object: nil)
                }
            }
        }
    }
}

// MARK: - Shelf

struct ShelfSettingsTab: View {

    @AppStorage(AppSettings.Key.shelfDurationSeconds)
    private var seconds = AppSettings.Default.shelfDurationSeconds

    private let options: [(String, Double)] = [
        ("30 seconds", 30), ("1 minute", 60), ("2 minutes", 120),
        ("5 minutes", 300), ("15 minutes", 900), ("1 hour", 3600)
    ]

    var body: some View {
        TabContainer {
            SettingsRow(
                "Keep files for:",
                detail: "How long a file waits on the shelf before it's put back where it came from. Applies to files dropped after you change this."
            ) {
                Picker("", selection: $seconds) {
                    ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }
}

// MARK: - Music

struct MusicSettingsTab: View {

    @AppStorage(AppSettings.Key.musicLingerSeconds)
    private var seconds = AppSettings.Default.musicLingerSeconds

    private let options: [(String, Double)] = [
        ("5 seconds", 5), ("10 seconds", 10), ("20 seconds", 20),
        ("30 seconds", 30), ("1 minute", 60)
    ]

    var body: some View {
        TabContainer {
            SettingsRow(
                "Stay after pausing:",
                detail: "How long the music island stays visible after playback pauses before it goes away. It never closes while your cursor is on it."
            ) {
                Picker("", selection: $seconds) {
                    ForEach(options, id: \.1) { Text($0.0).tag($0.1) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
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
            Image(systemName: "macwindow")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("Island")
                .font(.title.weight(.semibold))
            Text(version)
                .foregroundStyle(.secondary)
            Text("A notch for every display.")
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}
