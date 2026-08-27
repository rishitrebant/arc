import SwiftUI
import Combine

/// The Music activity module. Owns Detection (via `MusicService`), State,
/// and exposes Rendering (compact/expanded views) and Actions (playback
/// controls) — per Engineering Constitution's per-activity structure.
///
/// Sprint 2: backed by `MediaRemoteMusicService`, reading real system
/// now-playing state restricted to Apple Music / Spotify. This class only
/// knows the `MusicService` protocol, so `HardcodedMusicService` remains
/// available as a drop-in swap for previewing UI/animation work without a
/// real track playing — just change the default argument below.
@MainActor
final class MusicActivity: ObservableObject {
    static let kind: ActivityKind = .music

    @Published private(set) var isActive: Bool = false
    @Published private(set) var playbackState: MusicPlaybackState?

    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)
    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private let service: MusicService
    private var cancellables: Set<AnyCancellable> = []

    /// Retained state from before this activity last lost ownership, so
    /// resuming after a higher-priority interruption (e.g. a call) doesn't
    /// visually reset anything — per Call Philosophy, "nothing should reset
    /// unnecessarily."
    private var wasOwningIslandBeforeInterruption = false

    init(service: MusicService = MediaRemoteMusicService()) {
        self.service = service

        service.playbackStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state)
            }
            .store(in: &cancellables)

        service.start()
    }

    deinit {
        service.stop()
    }

    private func handle(_ state: MusicPlaybackState?) {
        playbackState = state
        let shouldBeActive = state != nil
        guard shouldBeActive != isActive else { return }
        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Actions

    func togglePlayPause() { service.togglePlayPause() }
    func skipForward() { service.skipForward() }
    func skipBackward() { service.skipBackward() }

    // MARK: - Activity lifecycle

    func didBecomeActive() {
        wasOwningIslandBeforeInterruption = false
    }

    func didResignActive() {
        wasOwningIslandBeforeInterruption = true
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {
        MusicIslandView(activity: self, isExpanded: isExpanded)
    }
}

extension MusicActivity: Activity {}
