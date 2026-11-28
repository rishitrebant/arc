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

    /// The card is up on its own for a moment after a device connects
    /// (or disconnects), then settles to the pill. Hovering brings it back.
    @Published private(set) var showsCard = false
    private var cardWorkItem: DispatchWorkItem?

    /// Battery of the device on screen, once it's been read.
    @Published private(set) var battery: BluetoothBattery?

    /// Everything connected right now, for the launcher.
    @Published private(set) var connected: [BluetoothDeviceInfo] = []

    /// Everything connected, whatever it is — the battery rings use this.
    @Published private(set) var allConnected: [BluetoothDeviceInfo] = []

    /// Last known battery per device address.
    @Published private(set) var batteries: [String: BluetoothBattery] = [:]

    private var lastBatteryRefresh = Date.distantPast

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

        monitor.onConnectedSetChanged = { [weak self] in
            self?.connectedSetChanged()
        }

        monitor.start()

        connected = monitor.currentConnected()
        allConnected = monitor.currentConnectedAll()
        refreshBatteries(force: true)
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Connected devices & battery

    private func connectedSetChanged() {

        connected = monitor.currentConnected()
        allConnected = monitor.currentConnectedAll()

        batteries = batteries.filter { entry in
            allConnected.contains { $0.address == entry.key }
        }

        // Devices report their battery a moment after connecting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.refreshBatteries(force: true)
        }
    }

    /// Reads every connected device's battery. Rate-limited so opening
    /// the launcher repeatedly doesn't spawn a probe each time.
    func refreshBatteries(force: Bool = false) {

        guard force || Date().timeIntervalSince(lastBatteryRefresh) > 60 else { return }

        lastBatteryRefresh = Date()

        for info in allConnected {

            Task { [weak self] in

                let level = await BluetoothBatteryReader.read(
                    address: info.address,
                    name: info.name
                )

                guard let self else { return }

                if let level, !level.isEmpty {
                    self.batteries[info.address] = level
                } else {
                    self.batteries[info.address] = nil
                }

                if self.device?.address == info.address {
                    self.battery = self.batteries[info.address]
                }
            }
        }
    }

    // MARK: - Detection → State

    private func handleConnect(_ info: BluetoothDeviceInfo) {

        guard AppSettings.showBluetoothAlert else { return }

        // Speakers and headphones only — never mice, keyboards, etc.
        guard info.isAudio else { return }

        if let last = lastShown[info.address],
           Date().timeIntervalSince(last) < Self.repeatSuppression {
            return
        }

        lastShown[info.address] = Date()

        device = info
        battery = batteries[info.address]
        phase = .connected

        setActive(true)
        presentCard()
        scheduleHideCheck(after: AnimationTokens.bluetoothDisplayDuration)
    }

    /// Shows the full card, then lets it settle to the pill.
    private func presentCard() {

        cardWorkItem?.cancel()

        showsCard = true
        announceLayoutChange()

        let work = DispatchWorkItem { [weak self] in
            self?.settleCard()
        }

        cardWorkItem = work

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.cardDuration, execute: work)
    }

    private func settleCard() {

        // Stays open under the cursor.
        guard !isIslandCurrentlyHovered() else {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverRecheckInterval) { [weak self] in
                self?.settleCard()
            }
            return
        }

        showsCard = false
        announceLayoutChange()
    }

    private func announceLayoutChange() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .islandLauncherLayoutChanged, object: nil)
        }
    }

    private static let cardDuration: TimeInterval = 2.8

    private func handleDisconnect(address: String) {

        // Only matters if it's the device on screen, and we didn't
        // cause it ourselves (that path shows its own confirmation).
        guard isActive, phase == .connected, device?.address == address else {
            return
        }

        hide()
    }

    // MARK: - Actions

    /// Disconnects any connected device by address — used by the
    /// launcher's device row. (The device card's own button goes through
    /// `disconnectDevice()`.)
    func disconnect(address: String) {

        guard monitor.disconnect(address: address) else { return }

        // The monitor's disconnect notification refreshes `connected`;
        // drop it from the list straight away so the row doesn't linger.
        connected.removeAll { $0.address == address }
        batteries[address] = nil
    }

    /// Called by the Disconnect button.
    func disconnectDevice() {

        guard phase == .connected, let device else { return }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        if monitor.disconnect(address: device.address) {

            phase = .disconnected
            presentCard()

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

        cardWorkItem?.cancel()
        cardWorkItem = nil
        showsCard = false

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

    /// The colour the island's shadow glows while this is showing.
    var shadowAccent: Color? {
        DesignTokens.Color.chargingAccent
    }

    /// The card shown on connect and under the cursor.
    var cardSize: CGSize {
        CGSize(width: DesignTokens.DeviceCard.width, height: DesignTokens.DeviceCard.height)
    }

    /// The pill it settles to.
    var pillSize: CGSize {
        CGSize(
            width: DesignTokens.AirDropMetrics.compactWidth,
            height: DesignTokens.AirDropMetrics.compactHeight
        )
    }

    var compactSize: CGSize { showsCard ? cardSize : pillSize }

    var expandedSize: CGSize { cardSize }

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
