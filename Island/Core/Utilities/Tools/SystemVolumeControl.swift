import Foundation
import CoreAudio

/// Reads and sets the system output volume (the default output device's
/// main volume) for the launcher's little volume control.
@MainActor
final class SystemVolumeControl: ObservableObject {

    /// When ARC itself last moved the volume — the volume pill stays out
    /// of the way for a moment after, or dragging a slider would swap the
    /// open card for the pill.
    nonisolated(unsafe) static var lastOwnChange = Date.distantPast

    @Published private(set) var level: Double = 0
    @Published private(set) var isAvailable = false

    private static let volumeSelector = AudioObjectPropertySelector(0x766D7663)   // 'vmvc' — virtual main volume

    private func defaultOutputDevice() -> AudioObjectID? {

        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id
        )

        return status == noErr && id != kAudioObjectUnknown ? id : nil
    }

    private var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: Self.volumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
    }

    func refresh() {

        guard let device = defaultOutputDevice() else {
            isAvailable = false
            return
        }

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = self.address

        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
            level = Double(min(max(volume, 0), 1))
            isAvailable = true
        } else {
            isAvailable = false
        }
    }

    func set(_ value: Double) {

        guard let device = defaultOutputDevice() else { return }

        Self.lastOwnChange = Date()

        var volume = Float32(min(max(value, 0), 1))
        var address = self.address

        if AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &volume
        ) == noErr {
            level = Double(volume)
        }
    }
}
