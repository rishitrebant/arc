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

    case music = 3
    case bluetooth = 4
    case airDrop = 5
    case downloads = 6
    case focus = 7
    case timer = 8

    static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
