import Foundation
import CoreAudio
import Combine

@MainActor
final class AudioOutputDeviceManager: ObservableObject {

    @Published private(set) var devices: [OutputDevice] = []

    func refresh() {

        let defaultID = Self.readDefaultOutputDevice()

        devices = Self.readOutputDevices(
            defaultDeviceID: defaultID
        )
    }

    func select(_ device: OutputDevice) {

        guard
            let audioDeviceID = UInt32(device.id),
            Self.setDefaultOutputDevice(audioDeviceID)
        else {
            return
        }

        refresh()
    }

    // MARK: - Default Device

    private static func readDefaultOutputDevice() -> AudioDeviceID {

        var deviceID: AudioDeviceID = 0

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(
            MemoryLayout<AudioDeviceID>.size
        )

        _ = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        return deviceID
    }

    // MARK: - Device Discovery

    private static func readOutputDevices(
        defaultDeviceID: AudioDeviceID
    ) -> [OutputDevice] {

        let systemObject =
            AudioObjectID(kAudioObjectSystemObject)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                systemObject,
                &address,
                0,
                nil,
                &dataSize
            ) == noErr
        else {
            return []
        }

        let count = Int(
            dataSize /
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )

        guard count > 0 else {
            return []
        }

        var deviceIDs = [AudioDeviceID](
            repeating: 0,
            count: count
        )

        let status: OSStatus = deviceIDs.withUnsafeMutableBufferPointer { buffer in

            guard let baseAddress = buffer.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }

            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }

        guard status == noErr else {
            return []
        }

        return deviceIDs.compactMap { deviceID in

            guard Self.hasOutputChannels(deviceID) else {
                return nil
            }

            guard Self.isPhysicalOutputDevice(deviceID) else {
                return nil
            }

            guard
                let name = Self.deviceName(deviceID),
                !name.isEmpty
            else {
                return nil
            }

            let isDefault =
                deviceID == defaultDeviceID

            return OutputDevice(
                id: String(deviceID),
                name: name,
                type: Self.deviceType(for: name),
                source: .system,
                isActive: isDefault,
                volume: Self.readVolume(deviceID)
            )
        }
    }

    // MARK: - Physical Output Filter

    private static func isPhysicalOutputDevice(
        _ deviceID: AudioDeviceID
    ) -> Bool {

        var transportType: UInt32 =
            kAudioDeviceTransportTypeUnknown

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(
            MemoryLayout<UInt32>.size
        )

        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &transportType
            ) == noErr
        else {
            return false
        }

        switch transportType {
        case
            kAudioDeviceTransportTypeBuiltIn,
            kAudioDeviceTransportTypeUSB,
            kAudioDeviceTransportTypeBluetooth,
            kAudioDeviceTransportTypeBluetoothLE,
            kAudioDeviceTransportTypeHDMI,
            kAudioDeviceTransportTypeDisplayPort,
            kAudioDeviceTransportTypeFireWire,
            kAudioDeviceTransportTypePCI,
            kAudioDeviceTransportTypeAVB:
            return true
        default:
            return false
        }
    }

    // MARK: - Device Name

    private static func deviceName(
        _ deviceID: AudioDeviceID
    ) -> String? {

        var name: Unmanaged<CFString>?

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var size = UInt32(
            MemoryLayout<Unmanaged<CFString>?>.size
        )

        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &name
            ) == noErr
        else {
            return nil
        }

        return name?.takeUnretainedValue() as String?
    }

    // MARK: - Output Channels

    private static func hasOutputChannels(
        _ deviceID: AudioDeviceID
    ) -> Bool {

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0

        guard
            AudioObjectGetPropertyDataSize(
                deviceID,
                &address,
                0,
                nil,
                &dataSize
            ) == noErr,
            dataSize > 0
        else {
            return false
        }

        let rawPointer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(dataSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )

        defer {
            rawPointer.deallocate()
        }

        let bufferList = rawPointer.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )

        guard
            AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &dataSize,
                bufferList
            ) == noErr
        else {
            return false
        }

        let buffers = UnsafeMutableAudioBufferListPointer(
            bufferList
        )

        return buffers.contains {
            $0.mNumberChannels > 0
        }
    }

    // MARK: - Volume

    private static func readVolume(
        _ deviceID: AudioDeviceID
    ) -> Double? {

        let elements: [AudioObjectPropertyElement] = [
            kAudioObjectPropertyElementMain,
            1,
            2
        ]

        for element in elements {

            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: element
            )

            var volume: Float32 = 0

            var size = UInt32(
                MemoryLayout<Float32>.size
            )

            let status = AudioObjectGetPropertyData(
                deviceID,
                &address,
                0,
                nil,
                &size,
                &volume
            )

            if status == noErr {
                return Double(
                    min(max(volume, 0), 1)
                )
            }
        }

        return nil
    }

    // MARK: - Set Default Output

    private static func setDefaultOutputDevice(
        _ deviceID: AudioDeviceID
    ) -> Bool {

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var selectedDeviceID = deviceID

        let size = UInt32(
            MemoryLayout<AudioDeviceID>.size
        )

        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &selectedDeviceID
        )

        return status == noErr
    }

    // MARK: - Icon Type

    private static func deviceType(
        for name: String
    ) -> OutputDeviceType {

        let value = name.lowercased()

        if value.contains("airpods")
            || value.contains("headphone")
            || value.contains("beats") {
            return .headphones
        }

        if value.contains("iphone")
            || value.contains("ipad")
            || value.contains("phone") {
            return .phone
        }

        if value.contains("tv")
            || value.contains("display")
            || value.contains("apple tv") {
            return .tv
        }

        if value.contains("airplay") {
            return .airplay
        }

        if value.contains("macbook")
            || value.contains("mac mini")
            || value.contains("mac studio")
            || value.contains("imac")
            || value.contains("mac pro")
            || value.contains("built-in")
            || value.contains("internal") {
            return .computer
        }

        return .speaker
    }
}
