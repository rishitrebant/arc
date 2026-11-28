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
        case clock
        case pomodoro
        case clipboard
        case notes
        case tools
        case camera
        case activity
    }

    /// The two clocks, side by side on the Clock page (Pomodoro has its own).
    enum ClockMode: String, CaseIterable, Identifiable {
        case timer
        case stopwatch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .timer: return "Timer"
            case .stopwatch: return "Stopwatch"
            }
        }
    }

    @Published private(set) var isActive: Bool = false
    @Published var page: Page = .home {
        didSet {
            updateKeyboardAccess()
            announceLayoutChange()
        }
    }

    /// Which clock the Clock page is showing.
    @Published var clockMode: ClockMode = .timer

    /// Set by `AppDelegate`: starts Keyboard Cleaning Mode. Returns false
    /// while macOS hasn't granted the permission it needs.
    var startCleaning: () -> Bool = { false }

    // Remembered between openings, like the Clock app's last-used values.
    @Published var timerMinutes: Int = 10
    @Published var focusMinutes: Int = 25
    @Published var breakMinutes: Int = 5

    /// Read-only window onto what's playing; the launcher never owns
    /// playback, it just shows and forwards controls.
    let music: MusicActivity

    /// A browser video — takes the Now Playing slot while it plays.
    let youtube: YouTubeActivity

    /// Running timers, listed on the home page like what's playing.
    let timer: TimerActivity

    /// How many running clocks the home page lists (it has room for two).
    var timerRowCount: Int { min(timer.activeSlots.count, 2) }

    private var lastTimerRowCount = 0

    /// One ring in the battery widget.
    struct BatteryItem: Identifiable, Equatable {
        let id: String
        let name: String
        let symbolName: String
        let percent: Int
        /// The Bluetooth address, for "Disconnect"; nil for this Mac.
        let address: String?
    }

    /// This Mac's charge, read each time the launcher opens.
    @Published private(set) var macBatteryPercent: Int?

    /// This Mac first, then each connected device whose level is known.
    var batteryItems: [BatteryItem] {

        var items: [BatteryItem] = []

        if let macBatteryPercent {
            items.append(BatteryItem(
                id: "mac", name: "This Mac", symbolName: "laptopcomputer",
                percent: macBatteryPercent, address: nil
            ))
        }

        for device in bluetooth.connected {
            if let level = bluetooth.batteries[device.address]?.headline {
                items.append(BatteryItem(
                    id: device.address, name: device.name, symbolName: device.symbolName,
                    percent: level, address: device.address
                ))
            }
        }

        return Array(items.prefix(4))
    }

    private let powerMonitor = PowerSourceMonitor()
    private var layoutCancellables: Set<AnyCancellable> = []

    /// The panel's height depends on the page and on what's running —
    /// tell the island so its own idea of the size follows.
    private func announceLayoutChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .islandLauncherLayoutChanged, object: nil)
        }
    }

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

        let wantsKeyboard = isActive && (page == .clock || page == .pomodoro || page == .clipboard || page == .notes)

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
        youtube: YouTubeActivity,
        timer: TimerActivity
    ) {

        self.music = music
        self.bluetooth = bluetooth
        self.youtube = youtube
        self.timer = timer

        bluetooth.$batteries
            .combineLatest(bluetooth.$connected)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in self?.announceLayoutChange() }
            .store(in: &layoutCancellables)

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(200), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.announceLayoutChange() }
            .store(in: &layoutCancellables)

        timer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self, self.timerRowCount != self.lastTimerRowCount else { return }
                self.lastTimerRowCount = self.timerRowCount
                self.announceLayoutChange()
            }
            .store(in: &layoutCancellables)

        clipboard.start()

        clipboard.$entries
            .map(\.count)
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.announceLayoutChange() }
            .store(in: &layoutCancellables)

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

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandOpenNotes
            ) {
                self?.showNotes()
            }
        })

        observers.append(Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: .islandTogglePinnedNote
            ) {
                let store = NoteStore.shared

                if store.pinned != nil {
                    store.unpin()
                } else if let newest = store.notes.first {
                    store.togglePin(newest.id)
                }
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

        let power = powerMonitor.currentSnapshot()
        macBatteryPercent = power.hasBattery ? power.percent : nil

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

    /// Opens the launcher on the notes page.
    private func showNotes() {

        guard AppSettings.launcherTrigger != .off else { return }

        if !isActive { show() }

        page = .notes
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

    /// Closes the launcher and opens the card behind its Now Playing row.
    func openNowPlayingCard() {

        hide()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: .islandExpandNow, object: nil)
        }
    }

    /// Locks the keyboard for cleaning and gets the launcher out of the way.
    func cleanKeyboard() {

        let started = startCleaning()

        // Without the permission macOS asks for it; stay here meanwhile.
        if started { hide() }
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

        typealias Metrics = DesignTokens.LauncherMetrics

        switch page {

        case .clipboard:
            // As tall as what's on it, not a fixed slab.
            let rows = min(clipboard.entries.count, Metrics.clipboardMaxRows)
            return CGSize(
                width: Metrics.clipboardWidth,
                height: rows == 0
                    ? Metrics.clipboardEmptyHeight
                    : Metrics.clipboardChrome + CGFloat(rows) * Metrics.clipboardRowHeight
            )

        case .notes:
            return CGSize(width: Metrics.notesWidth, height: Metrics.notesHeight)

        case .clock, .pomodoro:
            // The clock setup keeps the launcher's original size.
            return CGSize(width: Metrics.width, height: Metrics.height)

        case .tools:
            return CGSize(width: Metrics.width, height: Metrics.toolsHeight)

        case .camera:
            return CGSize(width: Metrics.cameraWidth, height: Metrics.cameraHeight)

        case .activity:
            return CGSize(width: Metrics.activityWidth, height: Metrics.activityHeight)

        case .home:
            let timerExtra = CGFloat(timerRowCount) * (Metrics.timerRowHeight + Metrics.sectionSpacing)

            let widget = AppSettings.launcherBatteryWidget
            let hasRings = !batteryItems.isEmpty

            // With the rings on, the devices are in them; otherwise the
            // connected device gets its own row.
            let showsDeviceRow = widget == .off && hasDevice
            let showsBottomRings = widget == .bottom && hasRings

            var height = Metrics.heightWithoutDevice + timerExtra

            if showsDeviceRow { height += Metrics.sectionSpacing + Metrics.deviceCardHeight }
            if showsBottomRings { height += Metrics.sectionSpacing + Metrics.batteryStripHeight }

            return CGSize(width: Metrics.homeWidth, height: height)
        }
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
            youtube: youtube,
            timer: timer
        )
    }
}

extension LauncherActivity: Activity {}
