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
    }

    enum Default {
        static let alwaysShowMenuBarIcon = false
        static let shelfDurationSeconds: Double = 60
        static let musicLingerSeconds: Double = 20
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
