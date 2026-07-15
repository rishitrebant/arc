import Foundation
import Combine

/// The ONLY interface the rest of the application is allowed to know about
/// for reading or controlling music playback.
///
/// This exists specifically to satisfy the Golden Rule tension flagged
/// earlier: reliable now-playing detection requires Apple's private
/// MediaRemote framework, which conflicts with the "public APIs only"
/// engineering principle. Isolating that reality behind this protocol means:
///
///   - MusicActivity, the views, and everything else in the app depend only
///     on this protocol and `MusicPlaybackState` — plain, private-API-free types.
///   - All private-framework usage lives in exactly one file,
///     `MediaRemoteMusicService.swift`.
///   - If Apple ever ships a public now-playing API, or App Store distribution
///     requires dropping MediaRemote, a new implementation of this protocol
///     is a drop-in replacement with zero changes anywhere else.
protocol MusicService {
    /// Emits a new snapshot any time playback state changes, and `nil` when
    /// nothing is playing from a supported app.
    var playbackStatePublisher: AnyPublisher<MusicPlaybackState?, Never> { get }

    func togglePlayPause()
    func skipForward()
    func skipBackward()

    /// Begins observing the system for now-playing changes.
    /// Call once at app launch.
    func start()

    /// Stops observation and releases any held resources.
    func stop()
}
