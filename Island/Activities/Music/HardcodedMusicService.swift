import Foundation
import Combine

/// Sprint 1 stand-in for `MusicService`.
///
/// Per Sprint 1 scope: no MediaRemote, no Spotify integration yet. This
/// simply publishes a fixed, hardcoded playback state matching the Figma
/// reference (`Ongoing music.png` / `Music Expanded.png` — "Pepas" by
/// Farruko) so the compact UI has something real to render.
///
/// This conforms to the exact same `MusicService` protocol a future
/// `MediaRemoteMusicService` will conform to — swapping this out later is a
/// one-line change in `MusicActivity.init`, nothing else in the app changes.
final class HardcodedMusicService: MusicService {
    private let stateSubject: CurrentValueSubject<MusicPlaybackState?, Never>

    var playbackStatePublisher: AnyPublisher<MusicPlaybackState?, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    init() {
        stateSubject = CurrentValueSubject(
            MusicPlaybackState(
                app: .appleMusic,
                title: "Pepas",
                artist: "Farruko",
                artwork: nil,
                isPlaying: true,
                elapsed: 130,   // 2:10, matches the measured Figma label
                duration: 285   // yields "-2:35" remaining, matches Figma
            )
        )
    }

    func togglePlayPause() {
        guard var state = stateSubject.value else { return }
        state.isPlaying.toggle()
        stateSubject.send(state)
    }

    func skipForward() { /* no-op in Sprint 1 */ }
    func skipBackward() { /* no-op in Sprint 1 */ }

    func start() { /* nothing to observe yet — state is fixed */ }
    func stop() { /* nothing to tear down */ }
}
