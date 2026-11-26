import Foundation
import CoreBluetooth

/// Battery levels for one Bluetooth device. Earbuds report left, right
/// and case separately; most other things report one number.
struct BluetoothBattery: Equatable {

    var main: Int?
    var left: Int?
    var right: Int?
    var caseLevel: Int?

    var isEmpty: Bool {
        main == nil && left == nil && right == nil && caseLevel == nil
    }

    /// The single number to show: the lowest earbud (the one that dies
    /// first), otherwise the device's own level.
    var headline: Int? {

        let buds = [left, right].compactMap { $0 }

        if let lowest = buds.min() { return lowest }

        return main ?? caseLevel
    }

    /// "L 80% · R 85% · Case 60%" for earbuds, nil for single-battery
    /// devices.
    var detail: String? {

        guard left != nil || right != nil else { return nil }

        var parts: [String] = []
        if let left { parts.append("L \(left)%") }
        if let right { parts.append("R \(right)%") }
        if let caseLevel { parts.append("Case \(caseLevel)%") }

        return parts.joined(separator: " · ")
    }
}

/// Finds a connected device's battery level, trying in turn:
///
/// 1. `system_profiler` — reports AirPods, Beats and Apple keyboards,
///    mice and trackpads (left/right/case where they have them).
/// 2. The standard Bluetooth LE Battery Service (0x180F) — many third
///    party mice, keyboards and headsets expose it.
///
/// Classic-Bluetooth speakers and headsets that use neither simply have
/// no readable level; for those this returns `nil` and the island shows
/// no battery rather than a made-up one.
@MainActor
enum BluetoothBatteryReader {

    static func read(address: String, name: String) async -> BluetoothBattery? {

        if let fromProfiler = await readFromSystemProfiler(address: address),
           !fromProfiler.isEmpty {
            return fromProfiler
        }

        if let level = await readFromPowerSources(name: name) {
            return BluetoothBattery(main: level)
        }

        if let level = await GATTBatteryReader(name: name).read() {
            return BluetoothBattery(main: level)
        }

        return nil
    }

    // MARK: - system_profiler

    private static func readFromSystemProfiler(address: String) async -> BluetoothBattery? {

        let wanted = normalise(address)

        return await Task.detached(priority: .utility) { () -> BluetoothBattery? in

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do { try process.run() } catch { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let sections = json["SPBluetoothDataType"] as? [[String: Any]]
            else {
                return nil
            }

            for section in sections {

                let devices = (section["device_connected"] as? [[String: Any]]) ?? []

                for entry in devices {
                    for (_, value) in entry {

                        guard
                            let info = value as? [String: Any],
                            let deviceAddress = info["device_address"] as? String,
                            Self.normalise(deviceAddress) == wanted
                        else {
                            continue
                        }

                        return BluetoothBattery(
                            main: Self.percent(info["device_batteryLevelMain"]),
                            left: Self.percent(info["device_batteryLevelLeft"]),
                            right: Self.percent(info["device_batteryLevelRight"]),
                            caseLevel: Self.percent(info["device_batteryLevelCase"])
                        )
                    }
                }
            }

            return nil

        }.value
    }

    // MARK: - Power sources

    /// Mice, keyboards and other accessories that macOS tracks as power
    /// sources (`pmset -g accps` lists them — the Logitech MX line shows
    /// up there but not in `system_profiler`).
    private static func readFromPowerSources(name: String) async -> Int? {

        await Task.detached(priority: .utility) { () -> Int? in

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            process.arguments = ["-g", "accps"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do { try process.run() } catch { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            guard
                let text = String(data: data, encoding: .utf8),
                let regex = try? NSRegularExpression(pattern: #"-(.+?) \(id=\d+\)\s+(\d+)%"#)
            else {
                return nil
            }

            func simple(_ text: String) -> String {
                text.lowercased()
                    .replacingOccurrences(of: "’", with: "'")
                    .trimmingCharacters(in: .whitespaces)
            }

            let wanted = simple(name)

            for line in text.split(separator: "\n") {

                let line = String(line)

                guard
                    let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                    let nameRange = Range(match.range(at: 1), in: line),
                    let levelRange = Range(match.range(at: 2), in: line),
                    let level = Int(line[levelRange])
                else {
                    continue
                }

                let accessory = simple(String(line[nameRange]))

                if accessory == wanted || accessory.contains(wanted) || wanted.contains(accessory) {
                    return level
                }
            }

            return nil

        }.value
    }

    private nonisolated static func normalise(_ address: String) -> String {
        address.uppercased().replacingOccurrences(of: "-", with: ":")
    }

    private nonisolated static func percent(_ value: Any?) -> Int? {
        guard let text = value as? String else { return nil }
        return Int(text.trimmingCharacters(in: CharacterSet(charactersIn: "% ")))
    }
}

// MARK: - BLE Battery Service

/// Reads the standard Battery Level characteristic (0x2A19) of an
/// already-connected Bluetooth LE peripheral, found by name. Gives up
/// after a few seconds so a device that won't answer never hangs the UI.
@MainActor
private final class GATTBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {

    private static let batteryService = CBUUID(string: "180F")
    private static let batteryLevel = CBUUID(string: "2A19")
    private static let timeout: TimeInterval = 6

    private let name: String
    private var central: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var continuation: CheckedContinuation<Int?, Never>?

    init(name: String) {
        self.name = name
        super.init()
    }

    func read() async -> Int? {

        await withCheckedContinuation { continuation in

            self.continuation = continuation

            central = CBCentralManager(delegate: self, queue: .main)

            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                self?.finish(nil)
            }
        }
    }

    private func finish(_ level: Int?) {

        guard let continuation else { return }

        self.continuation = nil

        if let peripheral {
            central?.cancelPeripheralConnection(peripheral)
        }

        continuation.resume(returning: level)
    }

    // MARK: CBCentralManagerDelegate (delivered on the main queue)

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {

        MainActor.assumeIsolated {

            guard central.state == .poweredOn else {
                if central.state != .unknown, central.state != .resetting {
                    finish(nil)
                }
                return
            }

            let candidates = central.retrieveConnectedPeripherals(
                withServices: [Self.batteryService]
            )

            guard let match = candidates.first(where: {
                $0.name?.caseInsensitiveCompare(name) == .orderedSame
            }) else {
                finish(nil)
                return
            }

            peripheral = match
            match.delegate = self
            central.connect(match)
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        MainActor.assumeIsolated {
            peripheral.discoverServices([Self.batteryService])
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        MainActor.assumeIsolated { finish(nil) }
    }

    // MARK: CBPeripheralDelegate

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        MainActor.assumeIsolated {

            guard let service = peripheral.services?.first else {
                finish(nil)
                return
            }

            peripheral.discoverCharacteristics([Self.batteryLevel], for: service)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        MainActor.assumeIsolated {

            guard let characteristic = service.characteristics?.first else {
                finish(nil)
                return
            }

            peripheral.readValue(for: characteristic)
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        MainActor.assumeIsolated {

            if let byte = characteristic.value?.first {
                finish(Int(byte))
            } else {
                finish(nil)
            }
        }
    }
}
