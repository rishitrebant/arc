import SwiftUI
import Combine

/// "Battery is low — turn on Low Power Mode?"
///
/// Takes the island when the battery falls to the percentage chosen in
/// Settings (`AppSettings.lowBatteryTriggerPercent`, default 20%) while
/// running on battery, and waits for a click. Clicking asks macOS to turn on Low
/// Power Mode (see `LowPowerModeController`), shows a short confirmation,
/// then returns the island to whatever was there before.
///
/// Fires once per drop below the threshold. It re-arms when the battery
/// is back above the threshold (e.g. after charging).
@MainActor
final class LowBatteryActivity: ObservableObject {

    static let kind: ActivityKind = .lowBattery

    enum Phase: Equatable {
        /// Waiting for the user to click.
        case prompt
        /// Password dialog is up / `pmset` is running.
        case enabling
        /// Low Power Mode is on — brief confirmation.
        case enabled
    }

    @Published private(set) var isActive: Bool = false
    @Published private(set) var batteryPercent: Int = 0
    @Published private(set) var phase: Phase = .prompt

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the island never auto-closes while the
    /// cursor is on it (same hook Music and Charging use).
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    private let monitor: PowerSourceMonitor
    private var hideWorkItem: DispatchWorkItem?

    /// True when the next drop to the threshold should raise the alert.
    private var isArmed = true

    private var cancellables: Set<AnyCancellable> = []

    /// Last settings values seen, so a change can be told apart from
    /// unrelated `UserDefaults` writes.
    private var lastTrigger = AppSettings.lowBatteryTriggerPercent
    private var lastEnabled = AppSettings.showLowBatteryAlert

    /// Safety net: re-reads the battery periodically in case a power
    /// notification is delayed or coalesced by macOS.
    private var pollTimer: Timer?
    private static let pollInterval: TimeInterval = 30

    /// `monitor` is optional (and created here) because a default
    /// argument can't construct a main-actor object.
    init(monitor providedMonitor: PowerSourceMonitor? = nil) {

        let monitor = providedMonitor ?? PowerSourceMonitor()

        self.monitor = monitor

        // Baseline. Launching the app while already low must not
        // pop the alert open — only a genuine drop does.
        let initial = monitor.currentSnapshot()
        batteryPercent = initial.percent
        isArmed = initial.percent > AppSettings.lowBatteryTriggerPercent

        monitor.onChange = { [weak self] snapshot in
            self?.handle(snapshot)
        }

        monitor.start()

        // Changing the alert level (or turning the alert on) in
        // Settings re-arms the alert and checks right away — so
        // setting the level to where the battery already is shows it
        // immediately, instead of waiting for the next percentage tick.
        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.settingsMayHaveChanged()
            }
            .store(in: &cancellables)

        pollTimer = Timer.scheduledTimer(
            withTimeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    private func refresh() {
        handle(monitor.currentSnapshot())
    }

    private func settingsMayHaveChanged() {

        let trigger = AppSettings.lowBatteryTriggerPercent
        let enabled = AppSettings.showLowBatteryAlert

        guard trigger != lastTrigger || enabled != lastEnabled else {
            return
        }

        lastTrigger = trigger
        lastEnabled = enabled

        isArmed = true
        refresh()
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Detection → State

    private func handle(_ snapshot: PowerSourceMonitor.Snapshot) {

        guard snapshot.hasBattery else {
            hide()
            return
        }

        batteryPercent = snapshot.percent

        let trigger = AppSettings.lowBatteryTriggerPercent

        // Shows in Xcode's console — handy for seeing why the alert
        // did or didn't appear.
        print(
            "🔋 LowBattery check — battery: \(snapshot.percent)%,"
            + " alert at: \(trigger)%,"
            + " plugged in: \(snapshot.isPluggedIn),"
            + " armed: \(isArmed),"
            + " alert enabled: \(AppSettings.showLowBatteryAlert),"
            + " Low Power Mode already on: \(LowPowerModeController.isEnabled)"
        )

        // Plugged in — the problem is solved, nothing to offer.
        if snapshot.isPluggedIn {

            hide()

            if snapshot.percent > trigger {
                isArmed = true
            }

            return
        }

        // On battery, comfortably above the threshold: just re-arm.
        guard snapshot.percent <= trigger else {
            isArmed = true
            return
        }

        guard
            isArmed,
            AppSettings.showLowBatteryAlert,
            !LowPowerModeController.isEnabled
        else {
            return
        }

        isArmed = false
        show()
    }

    // MARK: - Visibility

    private func show() {

        phase = .prompt
        setActive(true)
        scheduleHideCheck(after: AnimationTokens.lowBatteryDisplayDuration)
    }

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        setActive(false)
    }

    /// Hides after `delay` unless the cursor is on the island, or the
    /// password dialog is still open — in both cases it checks again
    /// shortly.
    private func scheduleHideCheck(after delay: TimeInterval) {

        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            if self.phase == .enabling || self.isIslandCurrentlyHovered() {
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

    /// Called when the user clicks the pill.
    func enableLowPowerMode() {

        guard phase == .prompt else { return }

        phase = .enabling

        // Stay put while macOS asks for the password.
        hideWorkItem?.cancel()
        hideWorkItem = nil

        LowPowerModeController.enable { [weak self] result in
            self?.handleEnableResult(result)
        }
    }

    private func handleEnableResult(_ result: LowPowerModeController.Result) {

        // The alert may have gone away while the dialog was open
        // (e.g. charger plugged in) — nothing left to update.
        guard isActive else { return }

        switch result {

        case .enabled:

            phase = .enabled

            // Short confirmation, then release the island — regardless
            // of hover, since the cursor is necessarily on it.
            hideWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                self?.hide()
            }

            hideWorkItem = work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + AnimationTokens.transientDisplayDuration,
                execute: work
            )

        case .cancelled:

            // Back to asking; give them a moment to change their mind.
            phase = .prompt
            scheduleHideCheck(after: AnimationTokens.lowBatteryDisplayDuration / 2)

        case .failed:

            // Couldn't do it automatically — hand over to System Settings.
            phase = .prompt
            LowPowerModeController.openBatterySettings()
            scheduleHideCheck(after: AnimationTokens.lowBatteryDisplayDuration / 2)
        }
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    /// A higher-priority activity took the island — drop the alert.
    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.LowBatteryMetrics.compactWidth,
            height: DesignTokens.LowBatteryMetrics.compactHeight
        )
    }

    /// Single layout, same as `ChargingActivity` — hover doesn't change
    /// the pill, so the AppKit hit region matches what's drawn.
    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        LowBatteryIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension LowBatteryActivity: Activity {}
