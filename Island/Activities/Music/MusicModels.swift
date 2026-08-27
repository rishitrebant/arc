import Foundation
import AppKit

/// Per Media Philosophy: "Music is sacred" — only these are ever recognized
/// as music sources. Everything else (Reels, browser video, voice notes) is
/// explicitly out of scope, and this enum is intentionally closed to avoid
/// accidental scope creep.
enum MusicApp: String {
    case appleMusic
    case spotify

    /// Bundle identifiers used to validate that now-playing info is actually
    /// coming from a supported app, not some other process also implementing
    /// the now-playing protocol.
    var bundleIdentifier: String {
        switch self {
        case .appleMusic: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    /// Reverse lookup used by `MediaRemoteMusicService` to check whether the
    /// system-reported "now playing" app is actually one of the two
    /// supported sources, before ever handing state to the rest of the app.
    /// Anything else (Safari/Reels, QuickTime, Voice Memos, random other
    /// process implementing the now-playing protocol) resolves to `nil`
    /// here and is treated identically to "nothing is playing."
    init?(bundleIdentifier: String) {
        switch bundleIdentifier {
        case MusicApp.appleMusic.bundleIdentifier: self = .appleMusic
        case MusicApp.spotify.bundleIdentifier: self = .spotify
        default: return nil
        }
    }
}

/// A single, immutable snapshot of now-playing state.
/// This is the only shape MusicService is allowed to hand to the rest of
/// the app — no MediaRemote types ever escape the Music module.
struct MusicPlaybackState: Equatable {
    var app: MusicApp
    var title: String
    var artist: String
    var artwork: NSImage?
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval

    static func == (lhs: MusicPlaybackState, rhs: MusicPlaybackState) -> Bool {
        lhs.app == rhs.app &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.isPlaying == rhs.isPlaying &&
        lhs.elapsed == rhs.elapsed &&
        lhs.duration == rhs.duration
        // artwork intentionally excluded from equality — image identity
        // isn't meaningful for state-change comparisons.
    }
}
