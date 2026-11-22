import Foundation
import CoreAudio
import CoreMediaIO
import CoreGraphics

/// Which sensors are in use right now.
struct PrivacySensors: OptionSet, Equatable {

    let rawValue: Int

    static let microphone = PrivacySensors(rawValue: 1 << 0)
    static let camera = PrivacySensors(rawValue: 1 << 1)
    static let screen = PrivacySensors(rawValue: 1 << 2)
}

/// Polls the system for microphone, camera and screen-recording use.
///
/// - Microphone: CoreAudio's "is running somewhere" flag on the default
///   input device — true whenever ANY process is capturing from it.
/// - Camera: the same flag on every CoreMediaIO video device.
/// - Screen recording: macOS has no public API for it. This looks for the
///   recording item macOS puts in the menu bar (a Control Center window
///   whose title contains "Recording"); treat it as best effort.
///
/// None of these need a privacy permission. Polled once a second — cheap,
/// and avoids a pile of property listeners across hot-plugged devices.
@MainActor
final class PrivacyMonitor {

    var onChange: ((PrivacySensors) -> Void)?

    private var timer: Timer?
    private var last: PrivacySensors = []

    /// What was in use at the last poll (the baseline, right after `start`).
    var current: PrivacySensors { last }

    func start() {

        guard timer == nil else { return }

        last = Self.current()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {

        let now = Self.current()

        guard now != last else { return }

        last = now
        onChange?(now)
    }

    // MARK: - Detection

    private static func current() -> PrivacySensors {

        var sensors: PrivacySensors = []

        if isMicrophoneRunning() { sensors.insert(.microphone) }
        if isCameraRunning() { sensors.insert(.camera) }
        if isScreenRecording() { sensors.insert(.screen) }

        return sensors
    }

    private static func isMicrophoneRunning() -> Bool {

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address, 0, nil, &size, &deviceID
            ) == noErr,
            deviceID != kAudioObjectUnknown
        else {
            return false
        }

        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)

        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        guard
            AudioObjectGetPropertyData(
                deviceID, &address, 0, nil, &size, &running
            ) == noErr
        else {
            return false
        }

        return running != 0
    }

    private static func isCameraRunning() -> Bool {

        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )

        var dataSize: UInt32 = 0

        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address, 0, nil, &dataSize
            ) == 0,
            dataSize > 0
        else {
            return false
        }

        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0

        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject),
                &address, 0, nil, dataSize, &used, &devices
            ) == 0
        else {
            return false
        }

        for device in devices {

            var running: UInt32 = 0
            let runningSize = UInt32(MemoryLayout<UInt32>.size)
            var used: UInt32 = 0

            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )

            if CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil, runningSize, &used, &running
            ) == 0, running != 0 {
                return true
            }
        }

        return false
    }

    private static func isScreenRecording() -> Bool {

        guard
            let windows = CGWindowListCopyWindowInfo(
                [.optionAll], kCGNullWindowID
            ) as? [[String: Any]]
        else {
            return false
        }

        return windows.contains { window in

            guard
                let owner = window[kCGWindowOwnerName as String] as? String,
                owner == "Control Center",
                let name = window[kCGWindowName as String] as? String
            else {
                return false
            }

            return name.localizedCaseInsensitiveContains("Recording")
        }
    }
}
