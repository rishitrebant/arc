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

        let shouldBeActive =
            state != nil

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
