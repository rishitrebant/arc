import Foundation
import AppKit

/// A browser the system can report as the Now Playing source.
struct WebBrowser {

    /// Bundle identifiers that report as this browser. WebKit's helper
    /// processes (what actually plays Safari's media) report their own
    /// identifier and name Safari as the parent.
    let bundleIDs: [String]

    /// The name AppleScript knows it by — `nil` for browsers with no
    /// scripting support (Firefox), which can't be checked for YouTube.
    let scriptName: String?

    /// Firefox-style browsers can't be inspected; everything else lists
    /// its tabs the Chromium way except Safari.
    let isSafari: Bool

    static let all: [WebBrowser] = [
        WebBrowser(bundleIDs: ["com.apple.Safari", "com.apple.SafariTechnologyPreview"],
                   scriptName: "Safari", isSafari: true),
        WebBrowser(bundleIDs: ["com.google.Chrome"],
                   scriptName: "Google Chrome", isSafari: false),
        WebBrowser(bundleIDs: ["com.microsoft.edgemac"],
                   scriptName: "Microsoft Edge", isSafari: false),
        WebBrowser(bundleIDs: ["com.brave.Browser"],
                   scriptName: "Brave Browser", isSafari: false),
        WebBrowser(bundleIDs: ["company.thebrowser.Browser"],
                   scriptName: "Arc", isSafari: false),
        WebBrowser(bundleIDs: ["com.vivaldi.Vivaldi"],
                   scriptName: "Vivaldi", isSafari: false),
        WebBrowser(bundleIDs: ["com.operasoftware.Opera"],
                   scriptName: "Opera", isSafari: false),
        WebBrowser(bundleIDs: ["org.mozilla.firefox"],
                   scriptName: nil, isSafari: false)
    ]

    /// The browser behind a Now Playing report, whichever process
    /// actually reported it.
    static func resolve(bundleID: String?, parentBundleID: String?) -> WebBrowser? {

        for candidate in [parentBundleID, bundleID].compactMap({ $0 }) {

            if let match = all.first(where: { $0.bundleIDs.contains(candidate) }) {
                return match
            }

            // Safari's media runs in "com.apple.WebKit.*" helpers.
            if candidate.hasPrefix("com.apple.WebKit") {
                return all.first { $0.isSafari }
            }
        }

        return nil
    }
}

/// A snapshot of a video playing in a browser — the only shape the
/// YouTube module hands to the rest of the app.
struct WebVideoState: Equatable {

    var title: String
    var channel: String
    var thumbnail: NSImage?
    var isPlaying: Bool
    var elapsed: TimeInterval
    var duration: TimeInterval

    /// `true` confirmed on YouTube, `false` confirmed NOT, `nil` couldn't
    /// be checked (no scripting, or access denied).
    var isYouTube: Bool?

    var browser: WebBrowser?

    static func == (lhs: WebVideoState, rhs: WebVideoState) -> Bool {
        lhs.title == rhs.title
            && lhs.channel == rhs.channel
            && lhs.isPlaying == rhs.isPlaying
            && lhs.elapsed == rhs.elapsed
            && lhs.duration == rhs.duration
            && lhs.isYouTube == rhs.isYouTube
        // Thumbnail identity isn't meaningful for change detection.
    }
}
