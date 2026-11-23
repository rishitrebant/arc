import SwiftUI
import Combine
import AppKit
import AVFoundation

extension Notification.Name {
    /// Asks `TimerActivity` to start a clock. `userInfo`:
    ///   - `"kind"`: `"countdown"`, `"stopwatch"` or `"pomodoro"`
    ///     (a bare `"duration"` with no kind means countdown; neither
    ///     means stopwatch).
    ///   - `"duration"`: seconds — the countdown, or the pomodoro's focus.
    ///   - `"breakDuration"`: seconds of the pomodoro's break.
    /// Posted by the launcher, menu bar, Settings and the Siri/Spotlight
    /// intents, so none of them needs a reference to the activity.
    static let islandStartTimer = Notification.Name("IslandStartTimer")

    /// Asks the island to open its launcher (now playing + timers) when
    /// nothing else owns it.
    static let islandOpenLauncher = Notification.Name("IslandOpenLauncher")
}

/// One running clock: either the countdown timer or the stopwatch.
///
/// A countdown and a stopwatch are independent slots, so both can run at
/// the same time. Time is derived from dates, not by counting ticks, so
/// it stays right across sleep and timer coalescing.
@MainActor
final class TimerSlot: ObservableObject {

    enum Kind: Equatable {
        case pomodoro
        case countdown
        case stopwatch
    }

    /// Which half of a pomodoro cycle is running.
    enum Stage: Equatable {
        case focus
        case rest
    }

    enum Phase: Equatable {
        case idle
        case running
        case paused
        case finished
    }

    let kind: Kind

    @Published private(set) var phase: Phase = .idle

    /// Whole seconds to show: remaining for a countdown, elapsed for a
    /// stopwatch. Only published when the whole second changes.
    @Published private(set) var displaySeconds: Int = 0

    @Published private(set) var stage: Stage = .focus

    /// Which focus session of the pomodoro this is, starting at 1.
    @Published private(set) var session: Int = 1

    var isActive: Bool { phase != .idle }

    /// Pomodoros and countdowns run down; the stopwatch runs up.
    var countsDown: Bool { kind != .stopwatch }

    private var focusDuration: TimeInterval = 0
    private var restDuration: TimeInterval = 0

    /// Length of the run currently counting down — what `progress` is
    /// measured against.
    private var totalDuration: TimeInterval = 0

    /// 1 → 0 as a countdown or pomodoro stage runs out. `nil` for the
    /// stopwatch, which has no end.
    var progress: Double? {

        guard countsDown, totalDuration > 0 else { return nil }

        return min(1, max(0, Double(displaySeconds) / totalDuration))
    }

    // Countdown: `endDate` while running, `remainingWhenPaused` otherwise.
    // Stopwatch: `startDate` while running, `elapsedWhenPaused` otherwise.
    private var endDate: Date?
    private var startDate: Date?
    private var remainingWhenPaused: TimeInterval = 0
    private var elapsedWhenPaused: TimeInterval = 0
    private var lastDuration: TimeInterval = 0

    private var ticker: Timer?
    private var tonePlayer: AVAudioPlayer?
    private var dismissWorkItem: DispatchWorkItem?

    init(kind: Kind) {
        self.kind = kind
    }

    // MARK: - Actions

    func start(duration: TimeInterval = 0) {

        reset()

        switch kind {
        case .pomodoro:
            // Use `startPomodoro` — a plain start can't know the break.
            return
        case .countdown:
            lastDuration = duration
            totalDuration = duration
            endDate = Date().addingTimeInterval(duration)
            remainingWhenPaused = duration
        case .stopwatch:
            startDate = Date()
            elapsedWhenPaused = 0
        }

        phase = .running
        refreshDisplay()
        startTicking()
    }

    func startPomodoro(focus: TimeInterval, rest: TimeInterval) {

        reset()

        focusDuration = focus
        restDuration = rest
        stage = .focus
        session = 1

        endDate = Date().addingTimeInterval(focus)
        remainingWhenPaused = focus
        totalDuration = focus

        phase = .running
        refreshDisplay()
        startTicking()
    }

    /// Focus → break → next focus, with no pause in between and a single
    /// chime to mark the change.
    private func advancePomodoro() {

        stage = stage == .focus ? .rest : .focus

        if stage == .focus { session += 1 }

        let next = stage == .focus ? focusDuration : restDuration

        endDate = Date().addingTimeInterval(next)
        remainingWhenPaused = next
        totalDuration = next

        playTone(loop: false)
        Haptics.confirm()

        refreshDisplay()
    }

    func togglePause() {

        switch phase {

        case .running:

            if countsDown {
                remainingWhenPaused = max(0, endDate?.timeIntervalSinceNow ?? 0)
                endDate = nil
            } else {
                elapsedWhenPaused = elapsed()
                startDate = nil
            }

            stopTicking()
            phase = .paused

        case .paused:

            if countsDown {
                endDate = Date().addingTimeInterval(remainingWhenPaused)
            } else {
                startDate = Date().addingTimeInterval(-elapsedWhenPaused)
            }

            phase = .running
            refreshDisplay()
            startTicking()

        case .idle, .finished:
            break
        }
    }

    /// Cancel / Stop — ends the clock whatever state it's in.
    func cancel() {
        reset()
        phase = .idle
        displaySeconds = 0
    }

    /// "Repeat" on a finished countdown — runs the same duration again.
    func restart() {
        guard phase == .finished, kind == .countdown else { return }
        start(duration: lastDuration)
    }

    private func reset() {
        stopTicking()
        stopChiming()
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        endDate = nil
        startDate = nil
    }

    // MARK: - Ticking

    private func startTicking() {

        stopTicking()

        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func stopTicking() {
        ticker?.invalidate()
        ticker = nil
    }

    private func tick() {

        guard phase == .running else { return }

        if countsDown, (endDate?.timeIntervalSinceNow ?? 0) <= 0 {

            if kind == .pomodoro {
                advancePomodoro()
            } else {
                finish()
            }

            return
        }

        refreshDisplay()
    }

    private func elapsed() -> TimeInterval {
        startDate.map { Date().timeIntervalSince($0) } ?? elapsedWhenPaused
    }

    private func refreshDisplay() {

        let seconds: Int

        if countsDown {
            let remaining = endDate?.timeIntervalSinceNow ?? remainingWhenPaused
            seconds = Int(max(0, remaining).rounded(.up))
        } else {
            seconds = Int(elapsed())
        }

        if seconds != displaySeconds {
            displaySeconds = seconds
        }
    }

    // MARK: - Presentation

    var accent: Color {
        switch kind {
        case .pomodoro:
            return stage == .focus
                ? DesignTokens.Color.pomodoroAccent
                : DesignTokens.Color.chargingAccent
        case .countdown, .stopwatch:
            return DesignTokens.Color.timerAccent
        }
    }

    var glyph: String {
        if phase == .finished { return "bell.fill" }
        switch kind {
        case .pomodoro: return stage == .focus ? "brain.head.profile" : "cup.and.saucer.fill"
        case .countdown: return "timer"
        case .stopwatch: return "stopwatch.fill"
        }
    }

    var title: String {
        if phase == .finished { return "Timer Done" }
        switch kind {
        case .pomodoro: return stage == .focus ? "Focus · Session \(session)" : "Break"
        case .countdown: return "Timer"
        case .stopwatch: return "Stopwatch"
        }
    }

    // MARK: - Finish (countdown only)

    private func finish() {

        stopTicking()

        endDate = nil
        remainingWhenPaused = 0
        displaySeconds = 0
        phase = .finished

        Haptics.confirm()
        playTone(loop: true)

        // Nobody came to stop it — don't hold the island forever.
        let work = DispatchWorkItem { [weak self] in
            self?.cancel()
        }

        dismissWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AnimationTokens.timerFinishedDuration,
            execute: work
        )
    }

    /// Apple's own timer tone — "Radar", the Clock app's default, which
    /// ships with macOS — looping until the timer is stopped (or the
    /// finished timer dismisses itself). Falls back to the system "Glass"
    /// alert if the file isn't there on some macOS version.
    private static let radarURL = URL(
        fileURLWithPath: "/System/Library/PrivateFrameworks/ToneLibrary.framework"
            + "/Versions/A/Resources/Ringtones/Radar.m4r"
    )

    private func playTone(loop: Bool) {

        tonePlayer?.stop()
        tonePlayer = nil

        if
            FileManager.default.fileExists(atPath: Self.radarURL.path),
            let player = try? AVAudioPlayer(contentsOf: Self.radarURL)
        {
            player.numberOfLoops = loop ? -1 : 0
            player.volume = 1
            player.prepareToPlay()
            player.play()
            tonePlayer = player
            return
        }

        NSSound(named: "Glass")?.play()
    }

    private func stopChiming() {
        tonePlayer?.stop()
        tonePlayer = nil
    }
}

/// A countdown timer and/or stopwatch that live in the notch — the Mac
/// equivalent of the iPhone's Timer live activity.
///
/// Unlike the transient activities (Charging, Bluetooth) this one stays
/// for as long as either clock exists: compact shows the time(s), hovering
/// expands to pause/resume and cancel controls. Starting a stopwatch
/// while a timer runs (or the reverse) adds a second clock rather than
/// replacing the first.
@MainActor
final class TimerActivity: ObservableObject {

    static let kind: ActivityKind = .timer

    let pomodoro = TimerSlot(kind: .pomodoro)
    let countdown = TimerSlot(kind: .countdown)
    let stopwatch = TimerSlot(kind: .stopwatch)

    @Published private(set) var isActive: Bool = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private var cancellables: Set<AnyCancellable> = []
    private var startObserver: Task<Void, Never>?

    /// The clocks currently on the island: pomodoro, timer, stopwatch.
    var activeSlots: [TimerSlot] {
        [pomodoro, countdown, stopwatch].filter(\.isActive)
    }

    init() {

        // Re-publish whenever a slot changes, so the view (which
        // observes this activity) redraws, and `isActive` follows.
        for slot in [pomodoro, countdown, stopwatch] {
            slot.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    DispatchQueue.main.async { self?.refreshActive() }
                }
                .store(in: &cancellables)
        }

        toggleObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandToggleStopwatch
            ) {
                guard let self else { return }

                if self.stopwatch.isActive {
                    self.stopwatch.cancel()
                } else {
                    self.stopwatch.start()
                }

                self.refreshActive()
            }
        }

        startObserver = Task { [weak self] in
            let notes = NotificationCenter.default.notifications(
                named: .islandStartTimer
            )
            for await note in notes {
                self?.start(userInfo: note.userInfo)
            }
        }
    }

    deinit {
        startObserver?.cancel()
        toggleObserver?.cancel()
    }

    private var toggleObserver: Task<Void, Never>?

    private func start(userInfo: [AnyHashable: Any]?) {

        let duration = userInfo?["duration"] as? TimeInterval
        let kind = userInfo?["kind"] as? String
            ?? (duration == nil ? "stopwatch" : "countdown")

        switch kind {

        case "pomodoro":
            pomodoro.startPomodoro(
                focus: max(60, duration ?? 25 * 60),
                rest: max(60, userInfo?["breakDuration"] as? TimeInterval ?? 5 * 60)
            )

        case "countdown":
            if let duration, duration > 0 {
                countdown.start(duration: duration)
            }

        default:
            stopwatch.start()
        }

        refreshActive()
    }

    private func refreshActive() {

        let shouldBeActive =
            pomodoro.isActive || countdown.isActive || stopwatch.isActive

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    /// A higher-priority activity took the island. The clocks keep
    /// running and `isActive` stays true, so the timer returns on its
    /// own once the interruption ends.
    func didResignActive() {}

    // MARK: - Sizing

    /// Each flank of the compact pill, sized to what it has to show.
    private var compactFlankWidth: CGFloat {

        typealias Metrics = DesignTokens.TimerMetrics

        let shown = activeSlots.prefix(2)
        let hasHours = shown.contains { $0.displaySeconds >= 3600 }

        if shown.count > 1 {
            return hasHours ? Metrics.flankWidthDualHours : Metrics.flankWidthDual
        }

        return hasHours ? Metrics.flankWidthHours : Metrics.flankWidth
    }

    /// The colour the island's shadow glows while this is showing.
    var shadowAccent: Color? {
        (activeSlots.first ?? stopwatch).accent
    }

    var compactSize: CGSize {

        return CGSize(
            width: DesignTokens.FileDropMetrics.notchWidth + compactFlankWidth * 2,
            height: DesignTokens.TimerMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.TimerMetrics.expandedWidth,
            height: activeSlots.count > 1
                ? DesignTokens.TimerMetrics.expandedHeaderHeight
                    + CGFloat(activeSlots.count) * DesignTokens.TimerMetrics.expandedRowHeightDual
                : DesignTokens.TimerMetrics.expandedHeight
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        TimerIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension TimerActivity: Activity {}
