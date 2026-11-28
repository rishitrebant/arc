import Foundation
import AVFoundation

/// Background sound for a Pomodoro's focus stretch, chosen in Settings.
enum FocusSound: String, CaseIterable, Identifiable {

    case off
    case rain
    case ocean
    case wind
    case fire
    case white
    case brown

    var id: String { rawValue }

    /// Which group it sits in, in the picker.
    enum Group: String {
        case nature = "Nature"
        case cozy = "Cozy"
        case noise = "Noise"
    }

    var group: Group? {
        switch self {
        case .rain, .ocean, .wind: return .nature
        case .fire: return .cozy
        case .white, .brown: return .noise
        case .off: return nil
        }
    }

    var symbol: String {
        switch self {
        case .off: return "speaker.slash"
        case .rain: return "cloud.rain"
        case .ocean: return "water.waves"
        case .wind: return "wind"
        case .fire: return "flame"
        case .white: return "waveform"
        case .brown: return "waveform.path"
        }
    }

    var title: String {
        switch self {
        case .off: return "Off"
        case .rain: return "Rain"
        case .ocean: return "Ocean"
        case .wind: return "Wind"
        case .fire: return "Fireplace"
        case .white: return "White noise"
        case .brown: return "Brown noise"
        }
    }

    /// The sound chosen right now.
    static var current: FocusSound {
        FocusSound(rawValue: UserDefaults.standard.string(forKey: AppSettings.Key.focusSound) ?? "") ?? .off
    }
}

/// Generates the sound itself — no audio files, nothing to download, and
/// it works offline. Fades in and out so starting or ending a focus
/// stretch never clicks.
@MainActor
final class FocusSoundPlayer: ObservableObject {

    static let shared = FocusSoundPlayer()

    /// The sound is actually playing right now.
    @Published private(set) var isAudible = false

    /// A focus stretch is running, so there should be sound…
    private var wanted = false

    /// …unless you paused it yourself from the Pomodoro card.
    private(set) var userPaused = false

    func setWanted(_ wanted: Bool) {
        self.wanted = wanted
        refresh()
    }

    func togglePaused() {
        userPaused.toggle()
        refresh()
    }

    func resume() {
        userPaused = false
        refresh()
    }

    /// Re-reads the chosen sound, volume and pause state.
    func refresh() {

        if wanted, !userPaused, FocusSound.current != .off {
            start()
        } else {
            stop()
        }
    }

    private var engine: AVAudioEngine?
    private var stopWork: DispatchWorkItem?

    /// Shared with the audio thread: written here, read there. A stale
    /// read is harmless — it only changes how fast the fade moves.
    private let state = RenderState()

    private final class RenderState: @unchecked Sendable {
        var target: Float = 0
        var kind: FocusSound = .off
    }

    private init() {}

    private func start() {

        let sound = FocusSound.current

        guard sound != .off else {
            stop()
            return
        }

        stopWork?.cancel()
        stopWork = nil

        let stored = UserDefaults.standard.object(forKey: AppSettings.Key.focusSoundVolume) as? Double
            ?? AppSettings.Default.focusSoundVolume

        isAudible = true

        state.kind = sound
        state.target = Float(min(max(stored, 0.05), 1)) * 0.5

        if engine == nil { buildEngine() }

        guard let engine, !engine.isRunning else { return }

        try? engine.start()
    }

    private func stop() {

        isAudible = false

        state.target = 0

        stopWork?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.engine?.stop()
            self?.engine = nil
        }

        stopWork = work

        // Long enough for the fade to reach silence.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func buildEngine() {

        let engine = AVAudioEngine()
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate

        guard
            sampleRate > 0,
            let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        else {
            return
        }

        let state = self.state

        var gain: Float = 0
        var brown: Float = 0
        var rainLow: Float = 0
        var drop: Float = 0
        var phase: Float = 0
        var oceanLow: Float = 0
        var windA: Float = 0
        var windB: Float = 0
        var windPhase: Float = 0
        var pop: Float = 0

        let source = AVAudioSourceNode(format: format) { _, _, frames, buffers in

            let list = UnsafeMutableAudioBufferListPointer(buffers)

            for frame in 0..<Int(frames) {

                gain += (state.target - gain) * 0.00004

                let white = Float.random(in: -1...1)
                var sample: Float

                switch state.kind {

                case .white, .off:
                    sample = white * 0.6

                case .brown:
                    brown = (brown + 0.02 * white) / 1.02
                    sample = brown * 3.2

                case .rain:
                    // Soft hiss that swells and falls slowly, with the
                    // odd drop landing on top of it.
                    rainLow += 0.35 * (white - rainLow)
                    phase += 0.15 / Float(sampleRate)
                    if phase > 1 { phase -= 1 }
                    let swell = 0.85 + 0.15 * sin(phase * 2 * .pi)

                    if Float.random(in: 0...1) < 0.0006 { drop = Float.random(in: 0.3...0.8) }
                    drop *= 0.996

                    sample = (rainLow * 0.9 + (white - rainLow) * 0.12) * swell * 0.8
                        + drop * white * 0.5

                case .ocean:
                    // Soft low rush that rises and recedes like waves.
                    oceanLow += 0.07 * (white - oceanLow)
                    phase += 0.085 / Float(sampleRate)
                    if phase > 1 { phase -= 1 }
                    let wave = 0.5 + 0.5 * sin(phase * 2 * .pi)
                    sample = oceanLow * (0.35 + 0.65 * wave) * 3.4

                case .wind:
                    // Breathy band of noise that swells slowly.
                    windA += 0.12 * (white - windA)
                    windB += 0.02 * (white - windB)
                    windPhase += 0.06 / Float(sampleRate)
                    if windPhase > 1 { windPhase -= 1 }
                    let gust = 0.45 + 0.55 * (0.5 + 0.5 * sin(windPhase * 2 * .pi))
                    sample = (windA - windB) * gust * 2.4

                case .fire:
                    // Low rumble with the odd crackle.
                    brown = (brown + 0.02 * white) / 1.02
                    if Float.random(in: 0...1) < 0.0011 { pop = Float.random(in: 0.35...1) }
                    pop *= 0.982
                    sample = brown * 1.8 + pop * white * 0.55
                }

                let value = sample * gain

                for buffer in list {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = value
                }
            }

            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)

        self.engine = engine
    }
}
