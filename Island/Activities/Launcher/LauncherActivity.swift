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
        case clipboard
    }

    @Published private(set) var isActive: Bool = false
    @Published var page: Page = .home {
        didSet { updateKeyboardAccess() }
    }

    // Remembered between openings, like the Clock app's last-used values.
    @Published var timerMinutes: Int = 10
    @Published var focusMinutes: Int = 25
    @Published var breakMinutes: Int = 5

    /// Read-only window onto what's playing; the launcher never owns
    /// playback, it just shows and forwards controls.
    let music: MusicActivity

    /// A browser video — takes the Now Playing slot while it plays.
    let youtube: YouTubeActivity

    /// Connected Bluetooth devices, shown subtly on the home page.
    let bluetooth: BluetoothActivity

    /// What you've copied recently.
    let clipboard = ClipboardHistory()

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate`: raises the launcher above whatever else is
    /// on the island while it's open.
    var requestElevation: (Bool) -> Void = { _ in }

    /// Set by `AppDelegate`: hands the keyboard back to the app in front.
    var releaseKeyboard: () -> Void = {}

    /// The island window only accepts typing while a number field is up.
    private func updateKeyboardAccess() {

        let wantsKeyboard = isActive && (page == .timer || page == .pomodoro)

        if wantsKeyboard {
            IslandWindow.allowsKeyboardFocus = true
        } else {
            releaseKeyboard()
        }
    }

    /// Whether the launcher currently holds the raised priority, so it
    /// asks for it once and gives it back once — never repeatedly.
    private var isElevated = false

    /// Set by `AppDelegate` — the menu never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    /// How long the launcher waits for the cursor to arrive (it can be
    /// opened by a shortcut with the cursor elsewhere) before closing.
    private static let arrivalGrace: TimeInterval = 4

    /// How long after the cursor leaves before the launcher collapses.
    private static let leaveDelay: TimeInterval = 0.5

    private var hoverTimer: Timer?
    private var shownAt = Date.distantPast
    private var hasBeenHovered = false
    private var leftAt: Date?
    private var observers: [Task<Void, Never>] = []

    init(
        music: MusicActivity,
        bluetooth: BluetoothActivity,
        youtube: YouTubeActivity
    ) {

        self.music = music
        self.bluetooth = bluetooth
        self.youtube = youtube

        clipboard.start()

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandOpenLauncher
            ) {
                // Hovering the notch can ask repeatedly — don't restart a
                // launcher that's already up.
                guard let self, !self.isActive else { return }
                self.show()
            }
        })

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandToggleLauncher
            ) {
                guard let self else { return }
                self.isActive ? self.hide() : self.show()
            }
        })

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandOpenClipboard
            ) {
                self?.showClipboard()
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
        let clipboard = self.clipboard
        Task { @MainActor in clipboard.stop() }
    }

    // MARK: - Visibility

    private func show() {

        // Turned off in Settings — this covers the shortcut and hover too.
        guard AppSettings.launcherTrigger != .off else { return }

        page = .home
        timerMinutes = AppSettings.lastTimerMinutes

        bluetooth.refreshBatteries()

        shownAt = Date()
        hasBeenHovered = false
        leftAt = nil

        if !isElevated {
            isElevated = true
            requestElevation(true)
        }

        setActive(true)
        startHoverWatch()
    }

    /// Opens the launcher straight onto the clipboard page (or switches
    /// to it if the launcher is already up).
    private func showClipboard() {

        guard AppSettings.launcherTrigger != .off else { return }

        if !isActive { show() }

        page = .clipboard
    }

    func hide() {

        hoverTimer?.invalidate()
        hoverTimer = nil

        setActive(false)

        // No number field any more — give the keyboard back.
        releaseKeyboard()

        if isElevated {
            isElevated = false
            requestElevation(false)
        }
    }

    /// Collapses the launcher shortly after the cursor leaves it — and
    /// only then, so it can stay open for as long as you're using it
    /// (copying several clipboard items, say).
    private func startHoverWatch() {

        hoverTimer?.invalidate()

        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHover() }
        }

        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func checkHover() {

        if isIslandCurrentlyHovered() {

            hasBeenHovered = true
            leftAt = nil

        } else if hasBeenHovered {

            let since = leftAt ?? Date()
            leftAt = since

            if Date().timeIntervalSince(since) > Self.leaveDelay {
                hide()
            }

        } else if Date().timeIntervalSince(shownAt) > Self.arrivalGrace {
            hide()
        }
    }

    private func setActive(_ shouldBeActive: Bool) {

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Actions

    func startTimer() {
        UserDefaults.standard.set(timerMinutes, forKey: AppSettings.Key.lastTimerMinutes)
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

    /// Puts an entry back on the clipboard. The launcher stays open so
    /// you can copy more; it closes when you move the cursor away.
    func copyBack(_ entry: ClipboardEntry) {
        clipboard.copyBack(entry)
        Haptics.confirm()
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

        // The home page has a Bluetooth row at the bottom only while a
        // device is connected; without one, don't leave its space empty.
        let hasDevice = !bluetooth.connected.isEmpty

        return CGSize(
            width: DesignTokens.LauncherMetrics.width,
            height: page == .home && !hasDevice
                ? DesignTokens.LauncherMetrics.heightWithoutDevice
                : DesignTokens.LauncherMetrics.height
        )
    }

    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        LauncherIslandView(
            activity: self,
            music: music,
            clipboard: clipboard,
            bluetooth: bluetooth,
            youtube: youtube
        )
    }
}

extension LauncherActivity: Activity {}
