import AppKit

/// Trackpad haptics, the way iOS taps your finger when the Dynamic Island
/// moves. Uses `NSHapticFeedbackManager`, which only produces feedback on
/// a Force Touch trackpad with a finger on it — everywhere else it's a
/// harmless no-op. Respects the "Haptic feedback" setting.
@MainActor
enum Haptics {

    /// A light tick — pressing a button, a stepper changing.
    static func tick() {
        perform(.alignment)
    }

    /// A firmer tap — the island opening, or a new activity arriving.
    static func open() {
        perform(.levelChange)
    }

    /// A generic tap — the island closing, or an action completing.
    static func confirm() {
        perform(.generic)
    }

    private static var lastFired: TimeInterval = 0
    private static let minimumSpacing: TimeInterval = 0.3

    private static func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern
    ) {

        guard AppSettings.hapticsEnabled else { return }

        // Taps closer together than this blur into one buzz. A click's
        // own tick is followed within milliseconds by the island's
        // "opening" tap (the button starts a timer, which hands the
        // island over) — the first one wins, the echo is dropped.
        let now = ProcessInfo.processInfo.systemUptime

        guard now - lastFired >= minimumSpacing else { return }

        lastFired = now

        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern,
            performanceTime: .now
        )
    }
}
