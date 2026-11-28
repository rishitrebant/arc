import SwiftUI
import ServiceManagement

/// Single source of truth for user-facing preferences, persisted in
/// `UserDefaults` via `@AppStorage` so the Settings window and the rest
/// of the app (which reads the static accessors below) always agree.
///
/// Keys live here, in one place. `NotchDisplayMode` keeps its own
/// existing key/storage — the Display tab just reads/writes that same
/// value, so nothing already saved gets lost.
enum AppSettings {

    enum Key {
        static let alwaysShowMenuBarIcon = "alwaysShowMenuBarIcon"
        static let shelfDurationSeconds = "shelfDurationSeconds"
        static let musicLingerSeconds = "musicLingerSeconds"
        static let showChargingIndicator = "showChargingIndicator"
        static let showChargerDisconnectedAlert = "showChargerDisconnectedAlert"
        static let showLowBatteryAlert = "showLowBatteryAlert"
        static let showBluetoothAlert = "showBluetoothAlert"
        static let showBluetoothInputDevices = "showBluetoothInputDevices"
        static let lowBatteryTriggerPercent = "lowBatteryTriggerPercent"
        static let showCapsLockIndicator = "showCapsLockIndicator"
        static let showCalendarAlerts = "showCalendarAlerts"
        static let calendarLeadMinutes = "calendarLeadMinutes"
        static let showPrivacyIndicators = "showPrivacyIndicators"
        static let showDownloadProgress = "showDownloadProgress"
        static let showFocusChanges = "showFocusChanges"
        static let youtubeControlsEnabled = "youtubeControlsEnabled"
        static let youtubeCompactIcon = "youtubeCompactIcon"
        static let youtubeDetection = "youtubeDetection"
        static let expandedTopCorners = "expandedTopCorners"
        static let launcherOpensOnHover = "launcherOpensOnHover"
        static let launcherTrigger = "launcherTrigger"
        static let launcherBatteryWidget = "launcherBatteryWidget"
        static let showDockIcon = "showDockIcon"
        static let notchGlowEnabled = "notchGlowEnabled"
        static let notchGlowColor = "notchGlowColor"
        static let notchGlowIntensity = "notchGlowIntensity"
        static let notchGlowOnHover = "notchGlowOnHover"
        static let hasSeenIntroGlow = "hasSeenIntroGlow"
        static let openClipboardOnPaste = "openClipboardOnPaste"
        static let hapticsEnabled = "hapticsEnabled"
        static let showAudioOutputChanges = "showAudioOutputChanges"
        static let globalShortcutsEnabled = "globalShortcutsEnabled"
        static let keepClipboardHistory = "keepClipboardHistory"
        static let lastTimerMinutes = "lastTimerMinutes"
        static let waterReminderEnabled = "waterReminderEnabled"
        static let cornerRoundness = "cornerRoundness"
        static let bounceAmount = "bounceAmount"
        static let volumeIndicatorEnabled = "volumeIndicatorEnabled"
        static let nextUpEnabled = "nextUpEnabled"
        static let showScreenTime = "showScreenTime"
        static let activityOwnsHover = "activityOwnsHover"
        static let focusSound = "focusSound"
        static let focusSoundVolume = "focusSoundVolume"
    }

    enum Default {
        static let alwaysShowMenuBarIcon = false
        static let shelfDurationSeconds: Double = 60
        static let musicLingerSeconds: Double = 20
        static let showChargingIndicator = true
        static let showChargerDisconnectedAlert = true
        static let showLowBatteryAlert = true
        static let showBluetoothAlert = true
        static let showBluetoothInputDevices = true
        static let lowBatteryTriggerPercent = 20
        static let showCapsLockIndicator = true
        static let showCalendarAlerts = true
        static let calendarLeadMinutes = 5
        static let showPrivacyIndicators = true
        static let showDownloadProgress = true
        static let showFocusChanges = true
        static let youtubeControlsEnabled = true
        static let youtubeCompactIcon = YouTubeCompactIcon.logo.rawValue
        static let youtubeDetection = YouTubeDetection.youtubeOnly.rawValue
        static let expandedTopCorners = ExpandedTopCorners.rounded.rawValue
        static let launcherOpensOnHover = false
        static let launcherTrigger = LauncherTrigger.notch.rawValue
        static let launcherBatteryWidget = LauncherBatteryWidget.off.rawValue
        static let showDockIcon = true
        static let notchGlowEnabled = false
        static let notchGlowColor = NotchGlowColor.white.rawValue
        static let notchGlowIntensity: Double = 1
        static let notchGlowOnHover = true
        static let openClipboardOnPaste = false
        static let hapticsEnabled = true
        static let showAudioOutputChanges = true
        static let globalShortcutsEnabled = true
        static let keepClipboardHistory = true
        static let lastTimerMinutes = 10
        static let waterReminderEnabled = false
        static let cornerRoundness: Double = 1
        static let bounceAmount: Double = 0.3
        static let volumeIndicatorEnabled = true
        static let nextUpEnabled = true
        static let showScreenTime = true
        static let activityOwnsHover = true
        static let focusSound = FocusSound.off.rawValue
        static let focusSoundVolume: Double = 0.5
    }

    // MARK: - Static accessors (for non-SwiftUI code)

    /// Read fresh every time it's used, so a change in Settings applies
    /// to the NEXT file dropped / NEXT pause — no relaunch needed.
    static var shelfDuration: TimeInterval {
        value(Key.shelfDurationSeconds, fallback: Default.shelfDurationSeconds)
    }

    static var musicLingerDuration: TimeInterval {
        value(Key.musicLingerSeconds, fallback: Default.musicLingerSeconds)
    }

    /// Read fresh at the moment of each plug-in, so toggling it in
    /// Settings applies to the very next time the charger is connected.
    static var showChargingIndicator: Bool {
        UserDefaults.standard.object(forKey: Key.showChargingIndicator) as? Bool
            ?? Default.showChargingIndicator
    }

    /// Battery percentage at or below which the low-battery alert
    /// fires. Read fresh on every battery update, so a change in
    /// Settings applies immediately.
    static var lowBatteryTriggerPercent: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.lowBatteryTriggerPercent)
        guard stored > 0 else { return Default.lowBatteryTriggerPercent }
        return min(max(stored, lowBatteryTriggerRange.lowerBound), lowBatteryTriggerRange.upperBound)
    }

    /// Allowed custom values for the low-battery alert level.
    static let lowBatteryTriggerRange = 1...99

    static var showChargerDisconnectedAlert: Bool {
        UserDefaults.standard.object(forKey: Key.showChargerDisconnectedAlert) as? Bool
            ?? Default.showChargerDisconnectedAlert
    }

    static var showBluetoothAlert: Bool {
        UserDefaults.standard.object(forKey: Key.showBluetoothAlert) as? Bool
            ?? Default.showBluetoothAlert
    }

    static var showBluetoothInputDevices: Bool {
        UserDefaults.standard.object(forKey: Key.showBluetoothInputDevices) as? Bool
            ?? Default.showBluetoothInputDevices
    }

    static var showCalendarAlerts: Bool {
        UserDefaults.standard.object(forKey: Key.showCalendarAlerts) as? Bool
            ?? Default.showCalendarAlerts
    }

    /// How many minutes before a meeting the island tells you.
    static var calendarLeadMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.calendarLeadMinutes)
        return stored > 0 ? stored : Default.calendarLeadMinutes
    }

    static var showPrivacyIndicators: Bool {
        UserDefaults.standard.object(forKey: Key.showPrivacyIndicators) as? Bool
            ?? Default.showPrivacyIndicators
    }

    static var showFocusChanges: Bool {
        UserDefaults.standard.object(forKey: Key.showFocusChanges) as? Bool
            ?? Default.showFocusChanges
    }

    static var youtubeControlsEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.youtubeControlsEnabled) as? Bool
            ?? Default.youtubeControlsEnabled
    }

    static var youtubeCompactIcon: YouTubeCompactIcon {
        YouTubeCompactIcon(
            rawValue: UserDefaults.standard.string(forKey: Key.youtubeCompactIcon) ?? ""
        ) ?? .logo
    }

    static var youtubeDetection: YouTubeDetection {
        YouTubeDetection(
            rawValue: UserDefaults.standard.string(forKey: Key.youtubeDetection) ?? ""
        ) ?? .youtubeOnly
    }

    /// How the top corners of every expanded card are drawn.
    static var expandedTopCorners: ExpandedTopCorners {
        ExpandedTopCorners(
            rawValue: UserDefaults.standard.string(forKey: Key.expandedTopCorners) ?? ""
        ) ?? .rounded
    }

    /// Open the launcher as soon as the cursor rests on the notch,
    /// instead of waiting for a click.
    static var launcherOpensOnHover: Bool {
        UserDefaults.standard.object(forKey: Key.launcherOpensOnHover) as? Bool
            ?? Default.launcherOpensOnHover
    }

    /// Where a click opens the launcher (or whether it opens at all).
    /// Multiplies every corner radius of the island (0.3 = nearly square,
    /// 1.4 = very round). Read each time a shape is drawn.
    static var cornerRoundness: Double {
        let stored = UserDefaults.standard.object(forKey: Key.cornerRoundness) as? Double
            ?? Default.cornerRoundness
        return min(max(stored, 0.3), 1.4)
    }

    /// How much the island overshoots when it opens (0 = none, 0.5 = a lot).
    static var bounceAmount: Double {
        let stored = UserDefaults.standard.object(forKey: Key.bounceAmount) as? Double
            ?? Default.bounceAmount
        return min(max(stored, 0), 0.5)
    }

    static var volumeIndicatorEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.volumeIndicatorEnabled) as? Bool
            ?? Default.volumeIndicatorEnabled
    }

    /// With something on the island (music, a timer…), hovering opens THAT
    /// and only a click on the notch opens the launcher.
    static var activityOwnsHover: Bool {
        UserDefaults.standard.object(forKey: Key.activityOwnsHover) as? Bool
            ?? Default.activityOwnsHover
    }

    static var nextUpEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.nextUpEnabled) as? Bool
            ?? Default.nextUpEnabled
    }

    static var launcherBatteryWidget: LauncherBatteryWidget {
        LauncherBatteryWidget(
            rawValue: UserDefaults.standard.string(forKey: Key.launcherBatteryWidget) ?? ""
        ) ?? .off
    }

    static var launcherTrigger: LauncherTrigger {
        LauncherTrigger(
            rawValue: UserDefaults.standard.string(forKey: Key.launcherTrigger) ?? ""
        ) ?? .notch
    }

    /// Whether ARC shows in the Dock and the app switcher. Off, it keeps
    /// running from the menu bar.
    static var showDockIcon: Bool {
        UserDefaults.standard.object(forKey: Key.showDockIcon) as? Bool
            ?? Default.showDockIcon
    }

    /// Open the launcher's clipboard page whenever ⌘V is pressed. Needs
    /// the Input Monitoring permission, so it's off until asked for.
    static var openClipboardOnPaste: Bool {
        UserDefaults.standard.object(forKey: Key.openClipboardOnPaste) as? Bool
            ?? Default.openClipboardOnPaste
    }

    static var hapticsEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.hapticsEnabled) as? Bool
            ?? Default.hapticsEnabled
    }

    static var showAudioOutputChanges: Bool {
        UserDefaults.standard.object(forKey: Key.showAudioOutputChanges) as? Bool
            ?? Default.showAudioOutputChanges
    }

    static var globalShortcutsEnabled: Bool {
        UserDefaults.standard.object(forKey: Key.globalShortcutsEnabled) as? Bool
            ?? Default.globalShortcutsEnabled
    }

    static var keepClipboardHistory: Bool {
        UserDefaults.standard.object(forKey: Key.keepClipboardHistory) as? Bool
            ?? Default.keepClipboardHistory
    }

    /// The timer length last started from the launcher — what the
    /// global shortcut starts.
    static var lastTimerMinutes: Int {
        let stored = UserDefaults.standard.integer(forKey: Key.lastTimerMinutes)
        return stored > 0 ? stored : Default.lastTimerMinutes
    }

    static var showDownloadProgress: Bool {
        UserDefaults.standard.object(forKey: Key.showDownloadProgress) as? Bool
            ?? Default.showDownloadProgress
    }

    static var showCapsLockIndicator: Bool {
        UserDefaults.standard.object(forKey: Key.showCapsLockIndicator) as? Bool
            ?? Default.showCapsLockIndicator
    }

    static var showLowBatteryAlert: Bool {
        UserDefaults.standard.object(forKey: Key.showLowBatteryAlert) as? Bool
            ?? Default.showLowBatteryAlert
    }

    static var alwaysShowMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: Key.alwaysShowMenuBarIcon) as? Bool
            ?? Default.alwaysShowMenuBarIcon
    }

    private static func value(_ key: String, fallback: Double) -> Double {
        let stored = UserDefaults.standard.double(forKey: key)
        return stored > 0 ? stored : fallback
    }

    // MARK: - Launch at login

    static var launchAtLoginEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns whether the change actually took effect — registration
    /// can fail (e.g. unsigned dev builds), and the UI should reflect
    /// reality rather than the toggle's requested state.
    @discardableResult
    static func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            debugLog("⚠️ Launch at login change failed: \(error)")
        }
        return launchAtLoginEnabled == enabled
    }

    // MARK: - Notifications

    /// Posted when a setting changes that other parts of the app need to
    /// react to immediately (menu bar icon visibility, display mode).
    static let didChange = Notification.Name("AppSettingsDidChange")
}


/// What the compact YouTube pill shows on its left.
enum YouTubeCompactIcon: String, CaseIterable {
    case logo
    case thumbnail

    var title: String {
        switch self {
        case .logo: return "YouTube logo"
        case .thumbnail: return "Video thumbnail"
        }
    }
}

/// Which browser media the YouTube controls take over.
enum YouTubeDetection: String, CaseIterable {

    /// Only videos ARC can confirm are on YouTube. (If a browser can't be
    /// checked — Firefox, or Automation access denied — the video is
    /// shown rather than silently ignored.)
    case youtubeOnly

    /// Any video or audio playing in a browser.
    case anyVideo

    var title: String {
        switch self {
        case .youtubeOnly: return "YouTube only"
        case .anyVideo: return "Any video in the browser"
        }
    }
}

/// The colour of the glow around the notch.
enum NotchGlowColor: String, CaseIterable {
    case white, blue, purple, pink, green, orange

    /// Drifts through the colours below, one fading into the next.
    case cycle

    /// What `cycle` steps through.
    static let cyclePalette: [NotchGlowColor] = [.blue, .purple, .pink, .orange, .green]

    var title: String { self == .cycle ? "Cycle through colours" : rawValue.capitalized }

    var color: Color {
        switch self {
        case .white: return Color.white
        case .blue: return Color(red: 0.25, green: 0.55, blue: 1.0)
        case .purple: return Color(red: 0.62, green: 0.38, blue: 1.0)
        case .pink: return Color(red: 1.0, green: 0.38, blue: 0.7)
        case .green: return Color(red: 0.25, green: 0.9, blue: 0.55)
        case .orange: return Color(red: 1.0, green: 0.6, blue: 0.2)
        case .cycle: return NotchGlowColor.blue.color
        }
    }
}

/// Where the launcher can be opened from.
/// Whether the launcher shows battery rings (this Mac and your connected
/// devices) along its bottom.
enum LauncherBatteryWidget: String, CaseIterable {

    case bottom
    case off

    var title: String {
        switch self {
        case .bottom: return "Along the bottom"
        case .off: return "Off"
        }
    }
}

enum LauncherTrigger: String, CaseIterable {

    /// Anywhere on the notch.
    case notch

    /// Only the very top edge of the screen, near the center.
    case topEdge

    /// Never — the launcher menu is turned off, shortcut included.
    case off

    var title: String {
        switch self {
        case .notch: return "Click the notch"
        case .topEdge: return "Click the top edge only"
        case .off: return "Off"
        }
    }
}

/// The top corners of an expanded card.
enum ExpandedTopCorners: String, CaseIterable {

    /// Fully rounded, like a floating card.
    case rounded

    /// Flat, flaring into the top of the screen — the same shape the
    /// compact pill has, so the island reads as one piece with the notch.
    case blended

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .blended: return "Blended into the notch"
        }
    }
}
