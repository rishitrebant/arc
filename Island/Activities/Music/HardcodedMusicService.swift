import Foundation
import Combine

final class HardcodedMusicService:
    MusicService {

    private let stateSubject =
        CurrentValueSubject<
            MusicPlaybackState?,
            Never
        >(

            MusicPlaybackState(

                app:
                    .appleMusic,

                title:
                    "Pepas",

                artist:
                    "Farruko",

                artwork:
                    nil,

                isPlaying:
                    true,

                elapsed:
                    130,

                duration:
                    285
            )
        )

    var playbackStatePublisher:
        AnyPublisher<
            MusicPlaybackState?,
            Never
        > {

        stateSubject
            .eraseToAnyPublisher()
    }

    func togglePlayPause() {

        guard
            var state =
                stateSubject.value
        else {
            return
        }

        state.isPlaying.toggle()

        stateSubject.send(
            state
        )
    }

    func skipForward() {
        // no-op
    }

    func skipBackward() {
        // no-op
    }

    // NEW
    func seek(
        to position:
            TimeInterval
    ) {

        guard
            var state =
                stateSubject.value
        else {
            return
        }

        state.elapsed =
            min(
                max(
                    position,
                    0
                ),

                state.duration
            )

        stateSubject.send(
            state
        )
    }

    func start() {}

    func stop() {}
}
