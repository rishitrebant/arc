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

    private static func perform(
        _ pattern: NSHapticFeedbackManager.FeedbackPattern
    ) {

        guard AppSettings.hapticsEnabled else { return }

        NSHapticFeedbackManager.defaultPerformer.perform(
            pattern,
            performanceTime: .now
        )
    }
}
