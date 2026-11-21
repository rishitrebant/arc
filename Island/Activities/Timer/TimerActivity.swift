import SwiftUI
import Combine
import AppKit

extension Notification.Name {
    /// Asks `TimerActivity` to start. `userInfo["duration"]` is a
    /// `TimeInterval` for a countdown; absent means a stopwatch. Posted by
    /// the menu bar and the Settings window so neither needs a reference
    /// to the activity.
    static let islandStartTimer = Notification.Name("IslandStartTimer")
}

/// One running clock: either the countdown timer or the stopwatch.
///
/// A countdown and a stopwatch are independent slots, so both can run at
/// the same time. Time is derived from dates, not by counting ticks, so
/// it stays right across sleep and timer coalescing.
@MainActor
final class TimerSlot: ObservableObject {

    enum Kind: Equatable {
        case countdown
        case stopwatch
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

    var isActive: Bool { phase != .idle }

    // Countdown: `endDate` while running, `remainingWhenPaused` otherwise.
    // Stopwatch: `startDate` while running, `elapsedWhenPaused` otherwise.
    private var endDate: Date?
    private var startDate: Date?
    private var remainingWhenPaused: TimeInterval = 0
    private var elapsedWhenPaused: TimeInterval = 0
    private var lastDuration: TimeInterval = 0

    private var ticker: Timer?
    private var chimeTimer: Timer?
    private var chimesLeft = 0
    private var dismissWorkItem: DispatchWorkItem?

    init(kind: Kind) {
        self.kind = kind
    }

    // MARK: - Actions

    func start(duration: TimeInterval = 0) {

        reset()

        switch kind {
        case .countdown:
            lastDuration = duration
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

    func togglePause() {

        switch phase {

        case .running:

            if kind == .countdown {
                remainingWhenPaused = max(0, endDate?.timeIntervalSinceNow ?? 0)
                endDate = nil
            } else {
                elapsedWhenPaused = elapsed()
                startDate = nil
            }

            stopTicking()
            phase = .paused

        case .paused:

            if kind == .countdown {
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

        if kind == .countdown, (endDate?.timeIntervalSinceNow ?? 0) <= 0 {
            finish()
            return
        }

        refreshDisplay()
    }

    private func elapsed() -> TimeInterval {
        startDate.map { Date().timeIntervalSince($0) } ?? elapsedWhenPaused
    }

    private func refreshDisplay() {

        let seconds: Int

        switch kind {
        case .countdown:
            let remaining = endDate?.timeIntervalSinceNow ?? remainingWhenPaused
            seconds = Int(max(0, remaining).rounded(.up))
        case .stopwatch:
            seconds = Int(elapsed())
        }

        if seconds != displaySeconds {
            displaySeconds = seconds
        }
    }

    // MARK: - Finish (countdown only)

    private func finish() {

        stopTicking()

        endDate = nil
        remainingWhenPaused = 0
        displaySeconds = 0
        phase = .finished

        chimesLeft = Int(AnimationTokens.timerFinishedDuration
            / AnimationTokens.timerChimeInterval)
        chime()

        let timer = Timer(
            timeInterval: AnimationTokens.timerChimeInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.chime() }
        }

        RunLoop.main.add(timer, forMode: .common)
        chimeTimer = timer

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

    private func chime() {

        guard chimesLeft > 0 else {
            stopChiming()
            return
        }

        chimesLeft -= 1
        (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
    }

    private func stopChiming() {
        chimeTimer?.invalidate()
        chimeTimer = nil
        chimesLeft = 0
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

    /// The clocks currently on the island, timer first.
    var activeSlots: [TimerSlot] {
        [countdown, stopwatch].filter(\.isActive)
    }

    init() {

        // Re-publish whenever a slot changes, so the view (which
        // observes this activity) redraws, and `isActive` follows.
        for slot in [countdown, stopwatch] {
            slot.objectWillChange
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                    DispatchQueue.main.async { self?.refreshActive() }
                }
                .store(in: &cancellables)
        }

        startObserver = Task { [weak self] in
            let notes = NotificationCenter.default.notifications(
                named: .islandStartTimer
            )
            for await note in notes {
                let duration = note.userInfo?["duration"] as? TimeInterval
                self?.start(duration: duration)
            }
        }
    }

    deinit {
        startObserver?.cancel()
    }

    /// `nil` starts a stopwatch, a duration starts the countdown.
    func start(duration: TimeInterval?) {

        if let duration, duration > 0 {
            countdown.start(duration: duration)
        } else {
            stopwatch.start()
        }

        refreshActive()
    }

    private func refreshActive() {

        let shouldBeActive = countdown.isActive || stopwatch.isActive

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

    var compactSize: CGSize {
        CGSize(
            width: activeSlots.count > 1
                ? DesignTokens.TimerMetrics.compactWidthDual
                : DesignTokens.TimerMetrics.compactWidth,
            height: DesignTokens.TimerMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.TimerMetrics.expandedWidth,
            height: activeSlots.count > 1
                ? DesignTokens.TimerMetrics.expandedHeightDual
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
