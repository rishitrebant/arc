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
    case music = 2
    case bluetooth = 3
    case airDrop = 4
    case downloads = 5
    case focus = 6
    case timer = 7

    static func < (lhs: ActivityKind, rhs: ActivityKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
