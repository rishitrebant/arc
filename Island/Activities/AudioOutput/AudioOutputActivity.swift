import SwiftUI
import Combine

/// "Sound is now playing through …"
///
/// Transient: when the default output switches (AirPods connect, AirPlay
/// starts, you plug into a display), the island shows the new device for
/// a few seconds. Hover for its name.
///
/// A short delay before showing lets a Bluetooth connect pill, which has
/// higher priority, go first without this one expiring behind it.
@MainActor
final class AudioOutputActivity: ObservableObject {

    static let kind: ActivityKind = .audioOutput

    @Published private(set) var isActive: Bool = false
    @Published private(set) var device: AudioOutputInfo?

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the pill never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    /// Devices often flap while connecting; wait for the dust to settle.
    private static let settleDelay: TimeInterval = 1.2

    private let monitor: AudioOutputMonitor
    private var showWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?

    init(monitor providedMonitor: AudioOutputMonitor? = nil) {

        let monitor = providedMonitor ?? AudioOutputMonitor()

        self.monitor = monitor

        monitor.onChange = { [weak self] info in
            self?.handle(info)
        }

        monitor.start()
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Detection → State

    private func handle(_ info: AudioOutputInfo) {

        guard AppSettings.showAudioOutputChanges else { return }

        showWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.show(info)
        }

        showWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.settleDelay,
            execute: work
        )
    }

    private func show(_ info: AudioOutputInfo) {

        device = info

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.audioOutputDisplayDuration)
    }

    // MARK: - Visibility

    private func hide() {

        showWorkItem?.cancel()
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

    /// The colour the island's shadow glows while this is showing.
    var shadowAccent: Color? {
        DesignTokens.Color.airDropAccent
    }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.BluetoothMetrics.expandedWidth,
            height: DesignTokens.BluetoothMetrics.expandedHeight
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        AudioOutputIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension AudioOutputActivity: Activity {}
