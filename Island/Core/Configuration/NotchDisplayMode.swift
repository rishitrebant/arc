import Foundation

/// Which screen(s) the Island should appear on. Persisted across launches
/// via `UserDefaults`.
///
/// Defaults to `.macBookOnly` — the built-in display is always the
/// intended home for this app; showing up on an external monitor is
/// opt-in, never automatic (see `AppDelegate.screensForCurrentMode`).
enum NotchDisplayMode: String, CaseIterable {

    case macBookOnly
    case externalOnly
    case both

    var menuTitle: String {
        switch self {
        case .macBookOnly: return "MacBook Only"
        case .externalOnly: return "External Monitor Only"
        case .both: return "Both"
        }
    }

    private static let userDefaultsKey = "notchDisplayMode"

    /// Reads/writes the persisted mode. Falls back to `.macBookOnly` on
    /// first launch (nothing saved yet) or if the saved value is ever
    /// unrecognized (e.g. a future case removed in an update).
    static var current: NotchDisplayMode {
        get {
            guard
                let raw = UserDefaults.standard.string(forKey: userDefaultsKey),
                let mode = NotchDisplayMode(rawValue: raw)
            else {
                return .macBookOnly
            }
            return mode
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: userDefaultsKey)
        }
    }
}
