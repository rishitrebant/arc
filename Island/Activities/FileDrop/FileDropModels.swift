import Foundation

/// One file currently sitting in the shelf.
///
/// Holds a COPY of the dropped file, in `ShelfFileStore`'s managed temp
/// directory — not just a reference to wherever it was dragged from.
///
/// That's a reversal from the original plan (a bare `URL` reference,
/// matching how NotchDrop does it) — worth being upfront about why.
/// Referencing works fine for a file dragged from a real, stable Finder
/// location. It breaks badly for the extremely common case of a file
/// handed over as a drag *promise* — screenshots, browser images, chat
/// attachments — which Cocoa materializes into a throwaway temp file
/// with a randomized name, one some sources delete again almost
/// immediately after the drag session ends. A bare reference to that
/// path goes stale within moments: exactly the generic broken-file icon
/// and garbled "f546...g.jpeg"-style filename this was built to avoid.
/// Copying costs a moment of disk I/O and briefly duplicates the file,
/// but the copy is cleaned up automatically (`ShelfFileStore.remove`)
/// the moment the item expires, is discarded, or is dragged out, so it's
/// never a real leak. The ORIGINAL file is left exactly where it was.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()

    /// Our own persisted copy — see `ShelfFileStore.persist`.
    let url: URL

    /// Where the file was dragged from. The original is never touched —
    /// dropping on the shelf COPIES — so this is informational only.
    let originalURL: URL

    /// Captured at drop time, from the drag's own suggested name where
    /// available — NOT derived from `url`'s filename, which carries a
    /// UUID prefix to avoid collisions in the shared temp directory.
    let displayName: String

    let addedAt: Date
    let expiresAt: Date

    /// Cheap existence check — called right before rendering/opening,
    /// not polled continuously. Now checking OUR OWN copy, not whatever
    /// the original drag source did with its file afterward.
    var fileStillExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

/// Where dropped files actually live while they're in the shelf, and
/// the copy/cleanup logic around that — see `ShelfItem`'s doc comment
/// for why this copies rather than just keeping a reference.
enum ShelfFileStore {

    static let directory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("IslandShelf", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true
        )
        return dir
    }()

    /// Copies `sourceURL` into our managed temp directory, returning
    /// the new stable URL, a display name, and `sourceURL` itself as
    /// `originalURL`. The original is NEVER modified or deleted — the
    /// shelf only ever holds a copy. `suggestedName` (from the drag's
    /// `NSItemProvider`, when available) is preferred over `sourceURL`'s
    /// own filename, since for promise-based drags that filename is
    /// usually the garbled temp one, not the original.
    static func persist(
        sourceURL: URL,
        suggestedName: String?
    ) -> (url: URL, displayName: String, originalURL: URL)? {

        let displayName = suggestedName ?? sourceURL.lastPathComponent
        let destination = directory.appendingPathComponent(
            UUID().uuidString + "-" + displayName
        )

        // `copyItem` doesn't reliably carry creation/modification dates
        // over (creation date is usually reset to "now"), so they're
        // re-applied to the copy — a file copied out of the shelf later
        // keeps the dates the original had.
        let originalAttributes =
            try? FileManager.default.attributesOfItem(atPath: sourceURL.path)

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            if let dates = dateAttributes(from: originalAttributes) {
                try? FileManager.default.setAttributes(
                    dates, ofItemAtPath: destination.path
                )
            }

            return (destination, displayName, sourceURL)
        } catch {
            return nil
        }
    }

    /// Pulls just `.creationDate`/`.modificationDate` out of a raw
    /// attributes dictionary. Returns `nil` if neither was present.
    private static func dateAttributes(
        from attributes: [FileAttributeKey: Any]?
    ) -> [FileAttributeKey: Any]? {

        guard let attributes else { return nil }

        var dates: [FileAttributeKey: Any] = [:]

        if let creationDate = attributes[.creationDate] as? Date {
            dates[.creationDate] = creationDate
        }

        if let modificationDate = attributes[.modificationDate] as? Date {
            dates[.modificationDate] = modificationDate
        }

        return dates.isEmpty ? nil : dates
    }

    static func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Tunable timings for the file-drop activity. Not wired to a settings UI
/// yet — `shelfDuration` is a plain constant per explicit instruction
/// ("keep it 1 min right now, we can make [the menu] later"). When that
/// menu gets built, this is the one value it should write back to.
enum FileDropConfiguration {

    /// How long a dropped file survives in the shelf before auto-removing.
    /// Comes from the Settings window (`AppSettings`), read fresh each
    /// time a file is dropped.
    static var shelfDuration: TimeInterval { AppSettings.shelfDuration }

    /// How long the shelf stays expanded immediately after a drop, before
    /// collapsing back to the compact chip row (the file itself stays in
    /// the shelf for the full `shelfDuration` — this only governs how
    /// long the EXPANDED reveal is shown).
    static let postDropRevealDuration: TimeInterval = 10

    /// How long a drag has to stay near the notch before the full panel
    /// commits to showing — per direct request: "a glow should appear
    /// as soon as the file is brought to it, then after half a second,
    /// the window should appear." Before this elapses, only the glow
    /// shows (`FileDropActivity.isDragNear`); Music (if playing) keeps
    /// showing normally the whole time.
    static let dragRevealDelay: TimeInterval = 0.5

    /// Grace period before a drag leaving the catch zone actually resets
    /// anything — see `FileDropActivity.dragExited`'s doc comment for
    /// why this exists. Bumped from an initial 0.25s: the physical notch
    /// rectangle (179×27, centered at the very top) is a genuine macOS
    /// dead zone for input — well documented by other developers
    /// (e.g. the MenuDown and NotchWall projects) hitting the exact same
    /// wall trying to interact with anything precisely under it — not
    /// something any NSWindow, at any level, can override. This can't
    /// make events fire inside that rectangle; what it CAN do is make
    /// sure a brief pass through it (dragging up from below, or sliding
    /// past it toward either side) doesn't visibly collapse the panel —
    /// 0.6s comfortably covers how long a real drag spends crossing a
    /// 27pt-tall gap without feeling sluggish to a genuine "drag away
    /// and give up" exit.
    static let dragExitGracePeriod: TimeInterval = 0.6
}
