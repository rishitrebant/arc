import SwiftUI
import Combine

/// The menu that opens when you click the empty notch: what's playing in
/// Music / Spotify, and one-tap ways to start a timer, a pomodoro or a
/// stopwatch.
///
/// Lowest priority — it only ever appears over an empty island, and any
/// other activity that wants the island simply takes it. It closes when
/// you click elsewhere, when you start something, or a few seconds after
/// the cursor leaves it.
@MainActor
final class LauncherActivity: ObservableObject {

    static let kind: ActivityKind = .launcher

    enum Page: Equatable {
        case home
        case timer
        case pomodoro
    }

    @Published private(set) var isActive: Bool = false
    @Published var page: Page = .home

    // Remembered between openings, like the Clock app's last-used values.
    @Published var timerMinutes: Int = 10
    @Published var focusMinutes: Int = 25
    @Published var breakMinutes: Int = 5

    /// Read-only window onto what's playing; the launcher never owns
    /// playback, it just shows and forwards controls.
    let music: MusicActivity

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the menu never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hideDelay: TimeInterval = 4
    private static let hoverRecheckInterval: TimeInterval = 1

    private var hideWorkItem: DispatchWorkItem?
    private var observers: [Task<Void, Never>] = []

    init(music: MusicActivity) {

        self.music = music

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandOpenLauncher
            ) {
                self?.show()
            }
        })

        // Click anywhere else on screen.
        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandRequestCollapse
            ) {
                self?.hide()
            }
        })
    }

    deinit {
        observers.forEach { $0.cancel() }
    }

    // MARK: - Visibility

    private func show() {

        page = .home
        setActive(true)
        scheduleHideCheck(after: Self.hideDelay)
    }

    func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        setActive(false)
    }

    private func scheduleHideCheck(after delay: TimeInterval) {

        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            if self.isIslandCurrentlyHovered() {
                self.scheduleHideCheck(after: Self.hoverRecheckInterval)
            } else {
                self.hide()
            }
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: work
        )
    }

    private func setActive(_ shouldBeActive: Bool) {

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Actions

    func startTimer() {
        TimerPreset.start(TimeInterval(timerMinutes * 60))
        hide()
    }

    func startPomodoro() {
        TimerPreset.startPomodoro(
            focus: TimeInterval(focusMinutes * 60),
            rest: TimeInterval(breakMinutes * 60)
        )
        hide()
    }

    func startStopwatch() {
        TimerPreset.start(nil)
        hide()
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    /// One fixed panel — hovering doesn't change it, so the hit region
    /// is exactly the panel.
    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.LauncherMetrics.width,
            height: DesignTokens.LauncherMetrics.height
        )
    }

    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        LauncherIslandView(
            activity: self,
            music: music
        )
    }
}

extension LauncherActivity: Activity {}
