import Foundation
import IOBluetooth

/// What the island needs to know about a Bluetooth device — nothing
/// IOBluetooth-specific leaks past `BluetoothMonitor`.
struct BluetoothDeviceInfo: Equatable, Identifiable {

    /// IOBluetooth's address string, e.g. "aa-bb-cc-dd-ee-ff".
    let address: String

    /// What the user sees. Falls back to "Bluetooth Device" for the
    /// rare device that doesn't report a name.
    let name: String

    /// SF Symbol chosen from the device's name and Bluetooth class.
    let symbolName: String

    /// Keyboards, mice and trackpads — they reconnect every time the Mac
    /// wakes, so the user can choose to not be told about them.
    let isInputDevice: Bool

    var id: String { address }
}

/// Watches Bluetooth devices connecting and disconnecting.
///
/// Uses IOBluetooth's connect/disconnect notifications, so events arrive
/// the moment they happen — no polling. Needs the
/// "Bluetooth Always Usage Description" key in the app's Info settings;
/// macOS shows a one-time permission prompt the first time this runs.
///
/// Only reports facts. What counts as worth showing, and for how long,
/// is `BluetoothActivity`'s decision.
@MainActor
final class BluetoothMonitor: NSObject {

    /// A device connected *after* the app was already running.
    var onConnect: ((BluetoothDeviceInfo) -> Void)?

    /// A device (by address) disconnected.
    var onDisconnect: ((String) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [String: IOBluetoothUserNotification] = [:]

    /// Devices we can act on (to disconnect them later).
    private var devices: [String: IOBluetoothDevice] = [:]

    /// Addresses currently connected. Anything already in here when a
    /// connect event arrives is not "new".
    private var connectedAddresses: Set<String> = []

    private var startDate = Date.distantFuture

    /// IOBluetooth may replay "connected" events for devices that were
    /// already connected when we registered. Anything inside this
    /// window after launch is treated as that replay, not a real
    /// connection.
    private static let startupGrace: TimeInterval = 2

    // MARK: - Lifecycle

    func start() {

        guard connectNotification == nil else { return }

        // Without this Info.plist entry macOS kills the whole app the
        // moment it touches Bluetooth. Check first, so a missing key
        // turns this feature off with a clear message instead of
        // crashing everything.
        guard Bundle.main.object(
            forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription"
        ) != nil else {
            print(
                "⚠️ Bluetooth popups are off: add \"Privacy - Bluetooth Always"
                + " Usage Description\" (NSBluetoothAlwaysUsageDescription)"
                + " to the Island target's Info settings, then rebuild."
            )
            return
        }

        startDate = Date()

        // Baseline: whatever is already connected must not pop the
        // island when the app launches.
        let paired = IOBluetoothDevice.pairedDevices() ?? []

        for case let device as IOBluetoothDevice in paired where device.isConnected() {

            guard let address = device.addressString, !address.isEmpty else {
                continue
            }

            devices[address] = device
            connectedAddresses.insert(address)
            watchForDisconnect(of: device, address: address)
        }

        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:fromDevice:))
        )
    }

    func stop() {

        connectNotification?.unregister()
        connectNotification = nil

        for notification in disconnectNotifications.values {
            notification.unregister()
        }

        disconnectNotifications.removeAll()
    }

    // MARK: - Actions

    /// Closes the connection to `address`. Returns whether it worked.
    func disconnect(address: String) -> Bool {

        guard let device = devices[address] else { return false }

        return device.closeConnection() == kIOReturnSuccess
    }

    // MARK: - IOBluetooth callbacks
    //
    // IOBluetooth does NOT call these on the main thread — it uses its
    // own background queue. (An earlier version assumed main and the
    // app stopped with a dispatch-queue assertion.) So each callback
    // hops to the main actor before touching any state.

    @objc private nonisolated func deviceConnected(
        _ notification: IOBluetoothUserNotification,
        fromDevice device: IOBluetoothDevice
    ) {
        Task { @MainActor in
            self.handleConnected(device)
        }
    }

    @objc private nonisolated func deviceDisconnected(
        _ notification: IOBluetoothUserNotification,
        fromDevice device: IOBluetoothDevice
    ) {
        Task { @MainActor in
            self.handleDisconnected(device, notification: notification)
        }
    }

    // MARK: - Handling

    private func handleConnected(_ device: IOBluetoothDevice) {

        guard let address = device.addressString, !address.isEmpty else {
            return
        }

        devices[address] = device
        watchForDisconnect(of: device, address: address)

        // Already known to be connected (launch baseline, or a
        // duplicate event) — not news.
        guard !connectedAddresses.contains(address) else { return }

        connectedAddresses.insert(address)

        guard Date().timeIntervalSince(startDate) > Self.startupGrace else {
            return
        }

        onConnect?(Self.info(for: device, address: address))
    }

    private func handleDisconnected(
        _ device: IOBluetoothDevice,
        notification: IOBluetoothUserNotification
    ) {

        notification.unregister()

        guard let address = device.addressString, !address.isEmpty else {
            return
        }

        disconnectNotifications[address] = nil
        connectedAddresses.remove(address)

        onDisconnect?(address)
    }

    private func watchForDisconnect(of device: IOBluetoothDevice, address: String) {

        guard disconnectNotifications[address] == nil else { return }

        disconnectNotifications[address] = device.register(
            forDisconnectNotification: self,
            selector: #selector(deviceDisconnected(_:fromDevice:))
        )
    }

    // MARK: - Device description

    private static func info(
        for device: IOBluetoothDevice,
        address: String
    ) -> BluetoothDeviceInfo {

        let rawName = (device.name ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Class of Device: bits 8–12 = major class, bits 2–7 = minor.
        let classOfDevice = UInt32(device.classOfDevice)
        let major = Int((classOfDevice >> 8) & 0x1F)
        let minor = Int((classOfDevice >> 2) & 0x3F)

        // Peripheral (0x05): minor bits 4–5 say keyboard / pointing.
        let isInputDevice = major == 0x05 && (minor & 0x30) != 0

        return BluetoothDeviceInfo(
            address: address,
            name: rawName.isEmpty ? "Bluetooth Device" : rawName,
            symbolName: symbol(name: rawName, major: major, minor: minor),
            isInputDevice: isInputDevice
        )
    }

    private static func symbol(name: String, major: Int, minor: Int) -> String {

        let lowered = name.lowercased()

        // Name wins: it's the most specific signal we have.
        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }
        if lowered.contains("trackpad") { return "rectangle.and.hand.point.up.left.fill" }
        if lowered.contains("keyboard") { return "keyboard.fill" }
        if lowered.contains("mouse") { return "computermouse.fill" }
        if lowered.contains("iphone") { return "iphone" }
        if lowered.contains("ipad") { return "ipad" }
        if lowered.contains("watch") { return "applewatch" }

        // Otherwise fall back to the Bluetooth class.
        switch major {

        case 0x01:                       // Computer
            return "laptopcomputer"

        case 0x02:                       // Phone
            return "iphone"

        case 0x04:                       // Audio / video
            switch minor {
            case 0x05, 0x07, 0x08:       // Loudspeaker, portable audio, car audio
                return "hifispeaker.fill"
            default:                     // Headset, hands-free, headphones…
                return "headphones"
            }

        case 0x05:                       // Peripheral
            switch minor & 0x30 {
            case 0x10, 0x30:             // Keyboard / combo
                return "keyboard.fill"
            case 0x20:                   // Pointing device
                return "computermouse.fill"
            default:                     // Joystick, gamepad…
                return "gamecontroller.fill"
            }

        case 0x07:                       // Wearable
            return "applewatch"

        default:
            return "dot.radiowaves.left.and.right"
        }
    }
}
