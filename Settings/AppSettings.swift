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
        static let hapticsEnabled = "hapticsEnabled"
        static let showAudioOutputChanges = "showAudioOutputChanges"
        static let globalShortcutsEnabled = "globalShortcutsEnabled"
        static let keepClipboardHistory = "keepClipboardHistory"
        static let lastTimerMinutes = "lastTimerMinutes"
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
        static let hapticsEnabled = true
        static let showAudioOutputChanges = true
        static let globalShortcutsEnabled = true
        static let keepClipboardHistory = true
        static let lastTimerMinutes = 10
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
