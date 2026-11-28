import SwiftUI
import Combine
import CoreAudio

/// The system volume changing, shown the way the rest of the island shows
/// things: a brief, quiet pill — a speaker glyph and a thin level bar —
/// that goes away on its own. Reads the default output device through
/// CoreAudio, so it needs no permission.
@MainActor
final class VolumeActivity: ObservableObject {

    static let kind: ActivityKind = .volume

    @Published private(set) var isActive = false
    @Published private(set) var level: Double = 0
    @Published private(set) var isMuted = false

    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private static let displayDuration: TimeInterval = 1.4

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var hideWork: DispatchWorkItem?
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultDeviceBlock: AudioObjectPropertyListenerBlock?
    private var lastLevel: Double?
    private var lastMuted: Bool?

    private static let volumeSelector = AudioObjectPropertySelector(0x766D7663)   // 'vmvc' — virtual main volume

    init() {

        attachToDefaultDevice()

        // Following the default output when it changes (headphones in…).
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.attachToDefaultDevice() }
        }

        defaultDeviceBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }

    // MARK: - CoreAudio

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

    private func attachToDefaultDevice() {

        detach()

        guard let id = defaultOutputDevice() else { return }

        device = id

        readState()
        lastLevel = level
        lastMuted = isMuted

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor in self?.volumeChanged() }
        }

        listenerBlock = block

        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {

            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block)
        }
    }

    private func detach() {

        guard device != kAudioObjectUnknown, let block = listenerBlock else { return }

        for selector in [Self.volumeSelector, kAudioDevicePropertyMute] {

            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )

            AudioObjectRemovePropertyListenerBlock(device, &address, DispatchQueue.main, block)
        }

        device = AudioObjectID(kAudioObjectUnknown)
        listenerBlock = nil
    }

    private func readState() {

        var volume = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: Self.volumeSelector,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) == noErr {
            level = Double(min(max(volume, 0), 1))
        }

        var muted = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)

        address.mSelector = kAudioDevicePropertyMute

        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr {
            isMuted = muted != 0
        }
    }

    // MARK: - Showing

    private func volumeChanged() {

        readState()

        defer {
            lastLevel = level
            lastMuted = isMuted
        }

        guard AppSettings.volumeIndicatorEnabled else { return }

        guard level != lastLevel || isMuted != lastMuted else { return }

        if !isActive {
            isActive = true
            isActiveSubject.send(true)
        }

        hideWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isActive = false
            self.isActiveSubject.send(false)
        }

        hideWork = work

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: work)
    }

    // MARK: - Activity

    func didBecomeActive() {}

    func didResignActive() {
        hideWork?.cancel()
        isActive = false
    }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.FileDropMetrics.notchWidth + 2 * 66,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize { compactSize }

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {
        VolumeIslandView(activity: self)
    }
}

extension VolumeActivity: Activity {}

private struct VolumeIslandView: View {

    @ObservedObject var activity: VolumeActivity

    private var symbol: String {
        if activity.isMuted || activity.level <= 0.001 { return "speaker.slash.fill" }
        if activity.level < 0.34 { return "speaker.wave.1.fill" }
        if activity.level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {

        ZStack(alignment: .top) {

            IslandShape(
                topRadius: DesignTokens.Shape.compactTopRadius,
                bottomRadius: DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)

            HStack(spacing: 0) {

                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 22)

                Spacer(minLength: 0)

                // The level: a thin capsule, never louder than the pill.
                ZStack(alignment: .leading) {

                    Capsule()
                        .fill(Color.white.opacity(0.22))

                    Capsule()
                        .fill(Color.white.opacity(activity.isMuted ? 0.35 : 0.95))
                        .frame(width: 44 * (activity.isMuted ? 0 : activity.level))
                }
                .frame(width: 44, height: 4)
            }
            .padding(.horizontal, 14)
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)
        }
        .frame(width: DesignTokens.sharedCanvasSize.width, height: DesignTokens.sharedCanvasSize.height, alignment: .top)
        .animation(.easeOut(duration: 0.12), value: activity.level)
        .animation(.easeOut(duration: 0.15), value: activity.isMuted)
    }
}
