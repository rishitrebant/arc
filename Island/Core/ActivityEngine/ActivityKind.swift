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
    /// Keyboard Cleaning Mode: the keyboard is locked, and this is how
    /// you see it (and unlock it). Above everything but an alert.
    case cleaning = 4

    case privacy = 5

    /// "Charger just plugged in" — a short-lived moment (see
    /// `ChargingActivity`). Above `music` so it can briefly take the
    /// island from whatever is playing and hand it straight back.
    case charging = 6

    /// "A Bluetooth device just connected" (see `BluetoothActivity`).
    case bluetooth = 7

    /// A meeting is about to start (see `CalendarActivity`).
    case calendar = 8

    /// Sound output switched to another device (see `AudioOutputActivity`).
    case audioOutput = 9

    /// Focus turned on / off (see `FocusActivity`) — a brief moment.
    case focus = 10

    /// A Caps Lock toggle moment (see `CapsLockActivity`).
    /// The hourly "drink some water" reminder — shown in the island, not
    /// the notification centre.
    case water = 11

    case capsLock = 12

    /// A running timer / stopwatch / pomodoro (see `TimerActivity`).
    /// Above `music` so a countdown stays visible while playing.
    /// The system volume changing: a brief, quiet pill.
    case volume = 13

    case timer = 14

    /// A video playing in the browser (see `YouTubeActivity`). Just
    /// above `music`: while one plays the other is paused anyway.
    case youtube = 15

    /// "Up next" — the song after this one, as the current one ends.
    case nextUp = 16

    case music = 17
    case airDrop = 18

    /// Files downloading (see `DownloadsActivity`). Below `music`: a
    /// long-running background task shouldn't push playback off the island.
    case downloads = 19

    /// The notch's click-to-open menu (see `LauncherActivity`). Lowest
    /// priority: it only ever appears over an empty island.
    /// A note the user pinned to the notch — always there, never urgent.
    case note = 20

    case launcher = 21

    static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
