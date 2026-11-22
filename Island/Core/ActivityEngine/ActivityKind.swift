import Foundation

/// Every kind of activity the island can display, ordered by priority.
///
/// Source note: PRODUCT.md contains two priority lists that disagree on the
/// order of AirDrop vs Downloads:
///   - "Feature Priorities" (Priority 2): Bluetooth, Downloads, AirDrop, Focus
///   - "Activity Priority System": Bluetooth(4), AirDrop(5), Downloads(6), Focus(7)
/// This enum follows the second, more explicit numbered list, since it reads
/// as the authoritative ordering. Flagging this discrepancy for confirmation —
/// swap AirDrop/Downloads below if the first list should win instead.
///
/// Lower `rawValue` = higher priority = wins ownership of the island.
enum ActivityKind: Int, Comparable, CaseIterable {
    case incomingCall = 0
    case activeCall = 1

    /// The "bring a file to the notch" shelf/AirDrop-sending activity.
    /// Deliberately placed above `music` — dragging a file to the notch
    /// (or having items sitting in the shelf) should take the island away
    /// from whatever Music is showing, and hand it back automatically
    /// once the shelf/drag interaction ends, per `ActivityManager`'s
    /// existing "activities return naturally" arbitration. Everything
    /// below shifted down by one to make room; nothing else about their
    /// relative order changed.
    case fileDrop = 2

    /// "Battery is low — turn on Low Power Mode?" (see
    /// `LowBatteryActivity`). An alert the user can act on, so it ranks
    /// above everything battery- or media-related, but still below
    /// calls and file drops.
    case lowBattery = 3

    /// Microphone / camera / screen recording just started (see
    /// `PrivacyActivity`). Above everything but calls and file drops —
    /// people should always notice a sensor turning on.
    case privacy = 4

    /// "Charger just plugged in" — a short-lived moment (see
    /// `ChargingActivity`). Above `music` so it can briefly take the
    /// island from whatever is playing and hand it straight back.
    case charging = 5

    /// "A Bluetooth device just connected" (see `BluetoothActivity`).
    case bluetooth = 6

    /// A meeting is about to start (see `CalendarActivity`).
    case calendar = 7

    /// A Caps Lock toggle moment (see `CapsLockActivity`).
    case capsLock = 8

    /// A running timer / stopwatch / pomodoro (see `TimerActivity`).
    /// Above `music` so a countdown stays visible while playing.
    case timer = 9

    case music = 10
    case airDrop = 11

    /// Files downloading (see `DownloadsActivity`). Below `music`: a
    /// long-running background task shouldn't push playback off the island.
    case downloads = 12

    case focus = 13

    /// The notch's click-to-open menu (see `LauncherActivity`). Lowest
    /// priority: it only ever appears over an empty island.
    case launcher = 14

    static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
