import Foundation
import Combine

protocol MusicService {

    var playbackStatePublisher:
        AnyPublisher<MusicPlaybackState?, Never> {
        get
    }

    func togglePlayPause()
    func skipForward()
    func skipBackward()

    // NEW
    func seek(to position: TimeInterval)

    func start()
    func stop()
}
