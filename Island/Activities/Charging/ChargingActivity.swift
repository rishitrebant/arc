import SwiftUI
import Combine

/// "Charger plugged in" — the Mac equivalent of the iPhone's Dynamic
/// Island charging moment.
///
/// Transient, like a notification that lives in the notch: it takes the
/// island when the power adapter is connected, stays for
/// `AnimationTokens.chargingDisplayDuration`, then releases ownership so
/// whatever was there before (Music, usually) comes straight back.
///
/// Detection → State → Activity → Rendering, same shape as every other
/// activity. Power facts come from `PowerSourceMonitor`; this class only
/// decides when to be visible.
@MainActor
final class ChargingActivity: ObservableObject {

    static let kind: ActivityKind = .charging

    @Published private(set) var isActive: Bool = false

    /// 0...100, kept live while the island is showing.
    @Published private(set) var batteryPercent: Int = 0

    /// Battery is full with the adapter connected — the label changes
    /// from "Charging" to "Charged".
    @Published private(set) var isFullyCharged: Bool = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — same hook `MusicActivity` uses. The
    /// island never auto-closes while the cursor is on it.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    private let monitor: PowerSourceMonitor
    private var wasPluggedIn: Bool?
    private var hideWorkItem: DispatchWorkItem?

    /// `monitor` is optional (and created here) because a default
    /// argument can't construct a main-actor object — default values
    /// are evaluated in a nonisolated context.
    init(monitor providedMonitor: PowerSourceMonitor? = nil) {

        let monitor = providedMonitor ?? PowerSourceMonitor()

        self.monitor = monitor

        // Baseline first. Launching the app with the charger already
        // connected is not a "plug in" event and must not pop the
        // island open.
        let initial = monitor.currentSnapshot()
        wasPluggedIn = initial.isPluggedIn
        batteryPercent = initial.percent
        isFullyCharged = initial.isFullyCharged

        monitor.onChange = { [weak self] snapshot in
            self?.handle(snapshot)
        }

        monitor.start()
    }

    deinit {
        // `deinit` isn't main-actor isolated; the monitor's own
        // teardown just removes a run-loop source.
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Detection → State

    private func handle(_ snapshot: PowerSourceMonitor.Snapshot) {

        guard snapshot.hasBattery else {
            hide()
            return
        }

        // Always keep the displayed numbers fresh.
        batteryPercent = snapshot.percent
        isFullyCharged = snapshot.isFullyCharged

        let previouslyPluggedIn = wasPluggedIn ?? snapshot.isPluggedIn
        wasPluggedIn = snapshot.isPluggedIn

        if snapshot.isPluggedIn && !previouslyPluggedIn {

            // Just plugged in.
            if AppSettings.showChargingIndicator {
                show()
            }

        } else if !snapshot.isPluggedIn {

            // Unplugged — nothing to say about charging any more.
            hide()
        }
    }

    // MARK: - Visibility

    private func show() {

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.chargingDisplayDuration)
    }

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        setActive(false)
    }

    /// Hides after `delay` unless the cursor is on the island, in which
    /// case it checks again shortly — identical behaviour to
    /// `MusicActivity`'s pause-hide timer.
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

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    /// A higher-priority activity (call, file drop) took the island.
    /// The charging moment is over — don't come back to it later.
    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    /// There is no separate expanded layout — hovering the pill leaves
    /// it as is (the same way the iPhone's charging pill doesn't
    /// change on touch). Reporting the same size for both keeps the
    /// AppKit hit region matched to what's actually drawn.
    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.ChargingMetrics.compactWidth,
            height: DesignTokens.ChargingMetrics.compactHeight
        )
    }

    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        ChargingIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension ChargingActivity: Activity {}
