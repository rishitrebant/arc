import SwiftUI
import Combine

/// "A Bluetooth device just connected."
///
/// Transient, like the charging moment: it takes the island when a
/// device connects, stays for `AnimationTokens.bluetoothDisplayDuration`,
/// then hands the island back. Hovering expands it to show the device's
/// name and a Disconnect button, and it stays open as long as the
/// cursor is on it.
///
/// Detection → State → Activity → Rendering, same shape as every other
/// activity. Device facts come from `BluetoothMonitor`; this class only
/// decides when to be visible.
@MainActor
final class BluetoothActivity: ObservableObject {

    static let kind: ActivityKind = .bluetooth

    enum Phase: Equatable {
        /// Device is connected — normal state.
        case connected
        /// User tapped Disconnect — brief confirmation.
        case disconnected
    }

    @Published private(set) var isActive: Bool = false
    @Published private(set) var device: BluetoothDeviceInfo?
    @Published private(set) var phase: Phase = .connected

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the island never auto-closes while the
    /// cursor is on it (same hook Music, Charging and Low Battery use).
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    private let monitor: BluetoothMonitor
    private var hideWorkItem: DispatchWorkItem?

    /// When each device last got a popup. Speakers and headsets often
    /// drop and reconnect several times in a row while pairing; without
    /// this, every reconnect restarted the timer and the pill never
    /// closed.
    private var lastShown: [String: Date] = [:]
    private static let repeatSuppression: TimeInterval = 15

    /// `monitor` is optional (and created here) because a default
    /// argument can't construct a main-actor object.
    init(monitor providedMonitor: BluetoothMonitor? = nil) {

        let monitor = providedMonitor ?? BluetoothMonitor()

        self.monitor = monitor

        monitor.onConnect = { [weak self] info in
            self?.handleConnect(info)
        }

        monitor.onDisconnect = { [weak self] address in
            self?.handleDisconnect(address: address)
        }

        monitor.start()
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Detection → State

    private func handleConnect(_ info: BluetoothDeviceInfo) {

        guard AppSettings.showBluetoothAlert else { return }

        if info.isInputDevice && !AppSettings.showBluetoothInputDevices {
            return
        }

        if let last = lastShown[info.address],
           Date().timeIntervalSince(last) < Self.repeatSuppression {
            return
        }

        lastShown[info.address] = Date()

        device = info
        phase = .connected

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.bluetoothDisplayDuration)
    }

    private func handleDisconnect(address: String) {

        // Only matters if it's the device on screen, and we didn't
        // cause it ourselves (that path shows its own confirmation).
        guard isActive, phase == .connected, device?.address == address else {
            return
        }

        hide()
    }

    // MARK: - Actions

    /// Called by the Disconnect button.
    func disconnectDevice() {

        guard phase == .connected, let device else { return }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        if monitor.disconnect(address: device.address) {

            phase = .disconnected

            // Short confirmation, then release the island — regardless
            // of hover, since the cursor is necessarily on it.
            let work = DispatchWorkItem { [weak self] in
                self?.hide()
            }

            hideWorkItem = work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + AnimationTokens.transientDisplayDuration,
                execute: work
            )

        } else {

            // Couldn't disconnect — stay as is, give them time.
            scheduleHideCheck(after: AnimationTokens.bluetoothDisplayDuration)
        }
    }

    // MARK: - Visibility

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        setActive(false)
    }

    /// Hides after `delay` unless the cursor is on the island, in which
    /// case it checks again shortly.
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

    /// A higher-priority activity took the island — drop this one.
    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    /// Compact reuses AirDrop's measured pill (icon left, status right).
    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.AirDropMetrics.compactWidth,
            height: DesignTokens.AirDropMetrics.compactHeight
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

        BluetoothIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension BluetoothActivity: Activity {}
