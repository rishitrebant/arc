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
        static let lowBatteryTriggerPercent = "lowBatteryTriggerPercent"
    }

    enum Default {
        static let alwaysShowMenuBarIcon = false
        static let shelfDurationSeconds: Double = 60
        static let musicLingerSeconds: Double = 20
        static let showChargingIndicator = true
        static let showChargerDisconnectedAlert = true
        static let showLowBatteryAlert = true
        static let lowBatteryTriggerPercent = 20
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
            print("⚠️ Launch at login change failed: \(error)")
        }
        return launchAtLoginEnabled == enabled
    }

    // MARK: - Notifications

    /// Posted when a setting changes that other parts of the app need to
    /// react to immediately (menu bar icon visibility, display mode).
    static let didChange = Notification.Name("AppSettingsDidChange")
}
