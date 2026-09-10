import SwiftUI
import Combine

@MainActor
final class MusicActivity: ObservableObject {

    static let kind: ActivityKind = .music

    @Published private(set) var isActive: Bool = false

    @Published private(set)
    var playbackState:
        MusicPlaybackState?

    private let isActiveSubject =
        CurrentValueSubject<
            Bool,
            Never
        >(false)

    var isActivePublisher:
        AnyPublisher<
            Bool,
            Never
        > {

        isActiveSubject
            .eraseToAnyPublisher()
    }

    private let service:
        MusicService

    private var cancellables:
        Set<AnyCancellable> = []

    private var wasOwningIslandBeforeInterruption =
        false

    // ---------------------------------------------------------------
    // Added: fixes "the music just does not go away." Previously
    // `shouldBeActive` was `state != nil` — true whenever MediaRemote
    // reports ANY loaded track, regardless of whether it's actually
    // playing. Apple Music/Spotify keep reporting the last track for a
    // long time after pausing (sometimes after quitting), so the
    // island never released ownership. Only this pause-handling path
    // is new; nothing else in this file changed.
    // ---------------------------------------------------------------
    private var pauseGraceTimer: DispatchWorkItem?
    private static let pauseGracePeriod: TimeInterval = 8

    init(
        service:
            MusicService =
            MediaRemoteMusicService()
    ) {

        self.service =
            service

        service
            .playbackStatePublisher
            .receive(
                on:
                    DispatchQueue.main
            )
            .sink {
                [weak self] state in

                self?.handle(
                    state
                )
            }
            .store(
                in:
                    &cancellables
            )

        service.start()
    }

    deinit {
        service.stop()
    }

    private func handle(
        _ state:
            MusicPlaybackState?
    ) {

        playbackState =
            state

        pauseGraceTimer?.cancel()
        pauseGraceTimer = nil

        if state?.isPlaying == true {

            setActive(true)

        } else if state == nil {

            // No track loaded at all — nothing to keep showing either
            // way, no need to wait.
            setActive(false)

        } else {

            // Paused, but a track is still loaded. Per direct request:
            // don't let the island sit forever just because SOMETHING
            // is loaded — but a short grace period first, so a quick
            // pause/skip/scrub doesn't cause a visible flash of hiding
            // and immediately reappearing.
            let work =
                DispatchWorkItem { [weak self] in
                    self?.setActive(false)
                }

            pauseGraceTimer =
                work

            DispatchQueue.main.asyncAfter(
                deadline: .now() + Self.pauseGracePeriod,
                execute: work
            )
        }
    }

    private func setActive(
        _ shouldBeActive: Bool
    ) {

        guard
            shouldBeActive != isActive
        else {
            return
        }

        isActive =
            shouldBeActive

        isActiveSubject.send(
            shouldBeActive
        )
    }

    // MARK: - Actions

    func togglePlayPause() {

        service.togglePlayPause()
    }

    func skipForward() {

        service.skipForward()
    }

    func skipBackward() {

        service.skipBackward()
    }

    // NEW
    func seek(
        to position:
            TimeInterval
    ) {

        service.seek(
            to:
                position
        )
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {

        wasOwningIslandBeforeInterruption =
            false
    }

    func didResignActive() {

        wasOwningIslandBeforeInterruption =
            true
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(
        isExpanded:
            Bool
    ) -> some View {

        MusicIslandView(
            activity:
                self,

            isExpanded:
                isExpanded
        )
    }
}

extension MusicActivity:
    Activity {}
