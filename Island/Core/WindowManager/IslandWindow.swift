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
        ignoresMouseEvents = false      // must remain false so hover/click work
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
