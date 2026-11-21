import AppIntents
import Foundation

/// Siri, Spotlight and Shortcuts entry points for the notch's clocks.
///
/// Each intent only posts the same `.islandStartTimer` notification the
/// launcher and menu bar use, so there is one code path for starting a
/// clock whatever asked for it.

struct StartTimerIntent: AppIntent {

    static let title: LocalizedStringResource = "Start Island Timer"
    static let description = IntentDescription(
        "Starts a countdown timer in the notch."
    )

    @Parameter(
        title: "Minutes",
        default: 10,
        inclusiveRange: (1, 999),
        requestValueDialog: "How many minutes?"
    )
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$minutes) minute timer")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimerPreset.start(TimeInterval(minutes * 60))
        return .result(dialog: "Timer set for \(minutes) minutes.")
    }
}

struct StartPomodoroIntent: AppIntent {

    static let title: LocalizedStringResource = "Start Island Pomodoro"
    static let description = IntentDescription(
        "Starts a focus session followed by a break, repeating until you cancel."
    )

    @Parameter(
        title: "Focus Minutes",
        default: 25,
        inclusiveRange: (1, 180)
    )
    var focusMinutes: Int

    @Parameter(
        title: "Break Minutes",
        default: 5,
        inclusiveRange: (1, 60)
    )
    var breakMinutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Start a \(\.$focusMinutes) minute pomodoro with \(\.$breakMinutes) minute breaks")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimerPreset.startPomodoro(
            focus: TimeInterval(focusMinutes * 60),
            rest: TimeInterval(breakMinutes * 60)
        )
        return .result(dialog: "Pomodoro started.")
    }
}

struct StartStopwatchIntent: AppIntent {

    static let title: LocalizedStringResource = "Start Island Stopwatch"
    static let description = IntentDescription(
        "Starts a stopwatch in the notch."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        TimerPreset.start(nil)
        return .result(dialog: "Stopwatch started.")
    }
}

/// What shows up in Spotlight and what Siri understands without any setup.
struct IslandShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {

        AppShortcut(
            intent: StartTimerIntent(),
            phrases: [
                "Start a timer in \(.applicationName)",
                "Start a \(.applicationName) timer"
            ],
            shortTitle: "Island Timer",
            systemImageName: "timer"
        )

        AppShortcut(
            intent: StartPomodoroIntent(),
            phrases: [
                "Start a pomodoro in \(.applicationName)",
                "Start focus in \(.applicationName)"
            ],
            shortTitle: "Island Pomodoro",
            systemImageName: "brain.head.profile"
        )

        AppShortcut(
            intent: StartStopwatchIntent(),
            phrases: [
                "Start a stopwatch in \(.applicationName)",
                "Start the \(.applicationName) stopwatch"
            ],
            shortTitle: "Island Stopwatch",
            systemImageName: "stopwatch"
        )
    }
}
