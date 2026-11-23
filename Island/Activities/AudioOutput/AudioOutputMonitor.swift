import Foundation
import CoreAudio

/// The sound output device, as the island shows it.
struct AudioOutputInfo: Equatable {

    let id: AudioObjectID
    let name: String
    /// SF Symbol that suits the device (AirPods, AirPlay, display…).
    let symbolName: String
}

/// Watches the system's default OUTPUT device and reports changes — the
/// moment AirPods take over, AirPlay starts, or a display's speakers
/// become the output.
///
/// Event-driven (a CoreAudio property listener), no polling.
@MainActor
final class AudioOutputMonitor {

    /// The output device changed to something else.
    var onChange: ((AudioOutputInfo) -> Void)?

    private var listener: AudioObjectPropertyListenerBlock?
    private(set) var current: AudioOutputInfo?

    private static var defaultOutputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {

        guard listener == nil else { return }

        // Baseline — launching isn't a change.
        current = Self.readDefaultOutput()

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.deviceMayHaveChanged() }
        }

        listener = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultOutputAddress,
            DispatchQueue.main,
            block
        )
    }

    func stop() {

        guard let listener else { return }

        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &Self.defaultOutputAddress,
            DispatchQueue.main,
            listener
        )

        self.listener = nil
    }

    private func deviceMayHaveChanged() {

        guard let info = Self.readDefaultOutput(), info != current else { return }

        current = info
        onChange?(info)
    }

    // MARK: - CoreAudio

    private static func readDefaultOutput() -> AudioOutputInfo? {

        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &defaultOutputAddress, 0, nil, &size, &deviceID
            ) == noErr,
            deviceID != kAudioObjectUnknown
        else {
            return nil
        }

        let name = stringProperty(deviceID, kAudioObjectPropertyName) ?? "Speakers"
        let transport = transportType(deviceID)

        return AudioOutputInfo(
            id: deviceID,
            name: name,
            symbolName: symbol(for: name, transport: transport)
        )
    }

    private static func stringProperty(
        _ device: AudioObjectID,
        _ selector: AudioObjectPropertySelector
    ) -> String? {

        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)

        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr,
            let value
        else {
            return nil
        }

        return value.takeRetainedValue() as String
    }

    private static func transportType(_ device: AudioObjectID) -> UInt32 {

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)

        AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)

        return value
    }

    private static func symbol(for name: String, transport: UInt32) -> String {

        let lowered = name.lowercased()

        if lowered.contains("airpods max") { return "airpodsmax" }
        if lowered.contains("airpods pro") { return "airpodspro" }
        if lowered.contains("airpods") { return "airpods" }

        switch transport {

        case kAudioDeviceTransportTypeAirPlay:
            return "airplayaudio"

        case kAudioDeviceTransportTypeBluetooth,
             kAudioDeviceTransportTypeBluetoothLE:
            return "headphones"

        case kAudioDeviceTransportTypeHDMI,
             kAudioDeviceTransportTypeDisplayPort:
            return "display"

        case kAudioDeviceTransportTypeBuiltIn:
            return "laptopcomputer"

        case kAudioDeviceTransportTypeUSB:
            return "hifispeaker.fill"

        default:
            return "speaker.wave.2.fill"
        }
    }
}
