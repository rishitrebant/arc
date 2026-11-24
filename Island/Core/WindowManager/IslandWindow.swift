import AppKit

/// A borderless, non-activating overlay window anchored to the notch.
///
/// Per PRODUCT.md's "Window Behaviour": no dock icon, no title bar, no
/// traffic lights, no focus stealing, no independent movement, no resizing
/// by the user. This window is a system surface, not an application window.
final class IslandWindow: NSPanel {

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1          // stays above the menu bar / notch UI
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        // Starting state doesn't matter much — `WindowManager` corrects it
        // immediately after creating this window (see `updateClickThrough`)
        // and keeps it continuously in sync with live cursor position from
        // then on. Starting `true` (click-through) just matches the more
        // common resting case, where most of this window's bounds aren't
        // over the visible pill.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    /// The island never takes keyboard focus — clicking it must not pull
    /// typing away from the app you're in — EXCEPT while the launcher is
    /// showing a number field the user can type into. The launcher turns
    /// this on for those pages and off again when they go away.
    static var allowsKeyboardFocus = false

    override var canBecomeKey: Bool { Self.allowsKeyboardFocus }
    override var canBecomeMain: Bool { false }
}
