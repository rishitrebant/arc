import SwiftUI
import Combine

/// "The microphone / camera / screen recording just turned on."
///
/// Transient: when a sensor that was off turns on, the island takes the
/// notch for a few seconds showing every sensor currently in use, in the
/// same colours iOS uses — orange microphone, green camera, purple
/// screen recording. Turning a sensor OFF is silent.
@MainActor
final class PrivacyActivity: ObservableObject {

    static let kind: ActivityKind = .privacy

    @Published private(set) var isActive: Bool = false

    /// Every sensor in use right now.
    @Published private(set) var sensors: PrivacySensors = []

    /// The one that just turned on — it names the pill.
    @Published private(set) var newest: PrivacySensors = .microphone

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the pill never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    private let monitor: PrivacyMonitor
    private var hideWorkItem: DispatchWorkItem?

    init(monitor providedMonitor: PrivacyMonitor? = nil) {

        let monitor = providedMonitor ?? PrivacyMonitor()

        self.monitor = monitor

        monitor.onChange = { [weak self] sensors in
            self?.handle(sensors)
        }

        monitor.start()

        // Baseline: a sensor already on at launch isn't "just turned on".
        sensors = monitor.current
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Detection → State

    private func handle(_ now: PrivacySensors) {

        let turnedOn = now.subtracting(sensors)

        sensors = now

        guard AppSettings.showPrivacyIndicators else { return }

        // Something turned off: keep what's showing accurate, but don't
        // pop the island open for it.
        guard !turnedOn.isEmpty else {
            if now.isEmpty { hide() }
            return
        }

        newest = turnedOn

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.privacyDisplayDuration)
    }

    // MARK: - Visibility

    private func hide() {

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

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    /// Single layout — hovering doesn't change it.
    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        PrivacyIslandView(activity: self)
    }
}

extension PrivacyActivity: Activity {}
