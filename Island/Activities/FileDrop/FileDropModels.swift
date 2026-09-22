import Foundation

/// One file currently sitting in the shelf.
///
/// Holds a COPY of the dropped file, in `ShelfFileStore`'s managed temp
/// directory — not just a reference to wherever it was dragged from. Per
/// direct request, `ShelfFileStore.persist` also deletes the original
/// source after this copy succeeds, so in practice the file MOVES onto
/// the shelf rather than being duplicated — but the shelf's own copy
/// remains the thing this type actually points at either way, which is
/// what the rest of this doc comment is about.
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
/// the moment the item is exported elsewhere, so it's never a real leak.
struct ShelfItem: Identifiable, Equatable {
    let id = UUID()

    /// Our own persisted copy — see `ShelfFileStore.persist`.
    let url: URL

    /// Where this file lived before it was moved onto the shelf. Per
    /// direct request: discarding an item (the trash button, the X on
    /// an individual item, or it simply expiring) without ever
    /// dragging it out somewhere restores it HERE instead of deleting
    /// it outright — see `FileDropActivity.removeShelfItem`. Only a
    /// genuine drag-out to a new destination (`FileDropActivity.
    /// completeExport`) skips the restore, since the whole point of
    /// that action was moving the file there instead.
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
/// the copy/cleanup/restore logic around that — see `ShelfItem`'s doc
/// comment for why this copies (then deletes the original) rather than
/// just keeping a reference.
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
    /// the new stable URL alongside a display name AND `sourceURL`
    /// itself (as `originalURL`) — callers keep that around so a later
    /// discard can restore the file there instead of deleting it. See
    /// `ShelfItem.originalURL`'s doc comment. `suggestedName` (from the
    /// drag's `NSItemProvider`, when available) is preferred over
    /// `sourceURL`'s own filename, since for promise-based drags that
    /// filename is usually the garbled temp one, not the original.
    static func persist(
        sourceURL: URL,
        suggestedName: String?
    ) -> (url: URL, displayName: String, originalURL: URL)? {

        let displayName = suggestedName ?? sourceURL.lastPathComponent
        let destination = directory.appendingPathComponent(
            UUID().uuidString + "-" + displayName
        )

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            // Per direct request: dropping a file onto the shelf now
            // REMOVES it from wherever it was dragged from, rather than
            // leaving a duplicate behind — the shelf becomes its only
            // home while it's there. Best-effort and silent on failure
            // by design: for a promise-backed drag (screenshots, browser
            // images — see `ShelfItem`'s doc comment above)
            // `sourceURL` is Cocoa's own disposable temp file, so
            // deleting it is harmless either way; for a real Finder file
            // this is the actual intended removal. If it can't be
            // deleted for any reason (permissions, already gone), the
            // shelf still has its own copy — this never blocks or fails
            // the drop itself. Note `sourceURL` is still returned as
            // `originalURL` regardless of whether this delete actually
            // succeeded — `restore` below re-creates the parent folder
            // if needed, so a later restore can still work even if this
            // particular delete failed (silently) or the folder gets
            // removed and recreated in the meantime.
            try? FileManager.default.removeItem(at: sourceURL)

            return (destination, displayName, sourceURL)
        } catch {
            return nil
        }
    }

    /// Moves the shelf's copy BACK to `originalURL` — used when an item
    /// is discarded (trashed, individually deleted, or expired) without
    /// ever being exported elsewhere. Best-effort: recreates the
    /// original parent folder if it's gone, and falls back to a
    /// "(restored)" suffix once if something already occupies the exact
    /// original path (never overwrites an unrelated file that's since
    /// taken that name). Returns whether the restore actually
    /// succeeded — callers should fall back to `remove(_:)` if not, so
    /// a shelf item is never left stuck with nowhere to go.
    static func restore(
        shelfURL: URL,
        to originalURL: URL
    ) -> Bool {

        let fileManager = FileManager.default

        try? fileManager.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var destination = originalURL

        if fileManager.fileExists(atPath: destination.path) {

            let ext = originalURL.pathExtension
            let base = originalURL.deletingPathExtension().lastPathComponent
            let fallbackName = ext.isEmpty
                ? "\(base) (restored)"
                : "\(base) (restored).\(ext)"

            destination = originalURL
                .deletingLastPathComponent()
                .appendingPathComponent(fallbackName)

            guard !fileManager.fileExists(atPath: destination.path) else {
                // Even the fallback name is taken — give up rather than
                // overwrite something unrelated. Caller falls back to
                // deleting the shelf copy instead.
                return false
            }
        }

        do {
            try fileManager.moveItem(at: shelfURL, to: destination)
            return true
        } catch {
            return false
        }
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
    static let shelfDuration: TimeInterval = 60

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
