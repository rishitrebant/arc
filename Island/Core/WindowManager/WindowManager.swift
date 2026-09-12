import AppKit
import SwiftUI

@MainActor
final class WindowManager {

    private var windows:
        [ObjectIdentifier: IslandWindow] = [:]

    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private var globalMouseDownMonitor: Any?

    /// Fired after `screenParametersChanged` repositions surviving
    /// windows — lets `AppDelegate` reconcile which screens should have
    /// an Island window at all (a screen can disconnect, or the user's
    /// `NotchDisplayMode` selection can change which ones are wanted).
    var onScreensChanged: (() -> Void)?

    /// Coalesces rapid-fire mouse events (a real drag can deliver
    /// `.leftMouseDragged` at 60-120Hz) into at most one pending
    /// recompute at a time, rather than queuing a `Task` per event.
    /// Piling up dozens of overlapping `Task`s that each synchronously
    /// touch `NSWindow.ignoresMouseEvents` — an AppKit property whose
    /// setter can itself trigger a layout pass — while SwiftUI is
    /// separately re-laying-out the same content in response to
    /// `@Published` changes is a very plausible source of the
    /// "-layoutSubtreeIfNeeded on a view which is already being laid
    /// out" recursion warning (and the crash that followed it).
    private var clickThroughUpdateScheduled = false

    /// Whether a drag is currently in progress — tracked from the
    /// EVENT TYPE that triggered the most recent mouse-tracking
    /// callback (`.leftMouseDragged` → true, `.mouseMoved`/`.leftMouseUp`
    /// → false), not from `NSEvent.pressedMouseButtons`.
    ///
    /// That polled hardware-button-state API turned out to be
    /// unreliable for exactly the input method this app's own hardware
    /// mostly uses: MacBook trackpad gesture-drags (three-finger drag,
    /// drag lock). macOS correctly delivers the `.leftMouseDragged`
    /// EVENT STREAM for those the whole time — which is why
    /// `updateAllClickThroughStates()` was still being called — but
    /// doesn't necessarily flip the underlying raw button-state flag
    /// `pressedMouseButtons` polls, since gesture-simulated drags and
    /// literal physical button state are arguably different things at
    /// that layer. The result was `dragMightBeInProgress` intermittently
    /// reading false mid-drag, so the catch-zone widening only "caught"
    /// on a lucky poll — precisely the flickering, "only works if I hit
    /// a very particular point" symptom. Deriving this from the event
    /// type itself instead avoids the mismatch entirely.
    private var lastKnownDragState = false

    private func noteDragState(from eventType: NSEvent.EventType) {

        switch eventType {
        case .leftMouseDragged:
            lastKnownDragState = true
        case .leftMouseUp, .mouseMoved:
            lastKnownDragState = false
        default:
            break
        }
    }

    private var activeScreenID:
        ObjectIdentifier?

    /// Screens whose island is currently docked.
    ///
    /// The window remains alive, but its visible island is hidden.
    /// We keep a small hit region at the top-center so the user can
    /// click or drag downward to restore it.
    private var dockedScreens:
        Set<ObjectIdentifier> = []

    /// How large the currently-owned activity's compact/expanded pill is.
    /// Defaults to Music's own sizes so behavior is unchanged if this is
    /// never set — `AppDelegate` sets it once at launch to read from
    /// whichever activity actually owns the island right now, via
    /// `ActivityManager`. This is what keeps the AppKit-level
    /// click-through hit region in sync with whatever's actually visible,
    /// activity by activity — see `Activity.compactSize`/`expandedSize`.
    var currentContentSize:
        () -> (compact: CGSize, expanded: CGSize) = {
            (
                CGSize(
                    width: DesignTokens.MusicMetrics.compactWidth,
                    height: DesignTokens.MusicMetrics.compactHeight
                ),
                CGSize(
                    width: DesignTokens.MusicMetrics.expandedWidth,
                    height: DesignTokens.MusicMetrics.expandedHeight
                )
            )
        }

    private var compactSize: CGSize {

        currentContentSize().compact
    }

    private var expandedSize: CGSize {

        currentContentSize().expanded
    }

    /// The window itself — unlike `compactSize`/`expandedSize` above,
    /// this is NOT activity-dependent and never changes at runtime. It's
    /// sized to comfortably fit the largest possible activity content
    /// AND the generous file-drag catch zone (see `updateAllClickThroughStates`),
    /// whichever is bigger. Keeping this fixed is deliberate — the whole
    /// island morph (including between completely different activities)
    /// is achieved by content resizing/repositioning ITSELF smoothly
    /// within this unchanging canvas, the same trick already used for
    /// Music's own compact↔expanded morph. Actually resizing the AppKit
    /// window on every activity change reintroduces the exact
    /// recentering flakiness that trick was built to avoid.
    private var canvasSize: CGSize {

        CGSize(

            width:
                max(
                    DesignTokens.sharedCanvasSize.width
                    + DesignTokens.Shadow.canvasInsetX * 2,

                    // Same `canvasInsetX * 2` term as above, deliberately —
                    // `centeredRoot` below applies that same padding around
                    // EVERYTHING it wraps, drag-catch layer included. Without
                    // accounting for it here too, the outer `.frame(width:)`
                    // would force a smaller width than the padding actually
                    // needs, and `DragCatchLayer` would end up centered
                    // slightly off from where `dragCatchZoneRect(for:)`
                    // (below) assumes it is on screen.
                    DesignTokens.FileDropMetrics.dragCatchZoneWidth
                    + DesignTokens.Shadow.canvasInsetX * 2
                ),

            height:
                max(
                    DesignTokens.sharedCanvasSize.height
                    + DesignTokens.Shadow.canvasInsetBottom,

                    DesignTokens.FileDropMetrics.dragCatchZoneHeight
                    + DesignTokens.Shadow.canvasInsetBottom
                )
        )
    }

    // MARK: - Present

    func present<Content: View>(
        _ rootView: Content,
        for screen: NSScreen
    ) {

        let screenID =
            ObjectIdentifier(screen)

        let origin =
            notchOrigin(
                on:
                    screen,

                size:
                    canvasSize
            )

        let panel =
            windows[screenID]
            ??
            IslandWindow(
                contentRect:
                    NSRect(
                        origin:
                            origin,

                        size:
                            canvasSize
                    )
            )

        let centeredRoot =
            rootView
                .padding(
                    EdgeInsets(
                        top:
                            0,

                        leading:
                            DesignTokens
                                .Shadow
                                .canvasInsetX,

                        bottom:
                            DesignTokens
                                .Shadow
                                .canvasInsetBottom,

                        trailing:
                            DesignTokens
                                .Shadow
                                .canvasInsetX
                    )
                )
                .frame(
                    width:
                        canvasSize.width,

                    height:
                        canvasSize.height,

                    alignment:
                        .top
                )

        let hosting =
            NSHostingView(
                rootView:
                    centeredRoot
            )

        hosting.frame =
            NSRect(
                origin:
                    .zero,

                size:
                    canvasSize
            )

        hosting.autoresizingMask =
            [.width, .height]

        panel.contentView =
            hosting

        panel.setFrameOrigin(
            origin
        )

        panel.orderFrontRegardless()

        windows[screenID] =
            panel

        startMouseTracking()

        updateAllClickThroughStates()
    }

    // MARK: - Monitor Changes

    /// Screens that currently have a live Island window. `AppDelegate`
    /// diffs its desired screen set against this to decide what to add
    /// or remove — see `AppDelegate.reconcileIslands`.
    var presentedScreenIDs: Set<ObjectIdentifier> {

        Set(windows.keys)
    }

    /// Where to anchor `NSSharingServicePicker` so it actually appears
    /// "right after the island" rather than at an arbitrary window
    /// corner — prefers whichever screen currently has the expanded
    /// panel active (`activeScreenID`), falling back to any live window
    /// if that's somehow unset. Returns view-LOCAL coordinates (window
    /// space, not screen space) since that's what
    /// `show(relativeTo:of:preferredEdge:)` expects.
    func airDropAnchor() -> (view: NSView, rect: NSRect)? {

        let screenID = activeScreenID ?? windows.keys.first

        guard
            let screenID,
            let window = windows[screenID],
            let contentView = window.contentView
        else {
            return nil
        }

        let expandedOnScreen =
            activeRectOnScreen(for: window, isExpanded: true)

        let localOrigin =
            window.convertPoint(fromScreen: expandedOnScreen.origin)

        let localRect =
            NSRect(origin: localOrigin, size: expandedOnScreen.size)

        return (contentView, localRect)
    }

    func removeAllWindows() {

        for window in windows.values {

            window.orderOut(nil)
        }

        windows.removeAll()

        dockedScreens.removeAll()

        activeScreenID =
            nil
    }

    /// Tears down the Island window for a single screen — the screen
    /// disconnected, or the user's `NotchDisplayMode` no longer wants an
    /// Island there.
    func removeWindow(
        for screenID: ObjectIdentifier
    ) {

        guard let window =
            windows[screenID]
        else {
            return
        }

        window.orderOut(nil)

        windows.removeValue(
            forKey: screenID
        )

        dockedScreens.remove(
            screenID
        )

        if activeScreenID == screenID {

            activeScreenID =
                nil
        }

        updateAllClickThroughStates()
    }

    func repositionAllWindows() {

        for screen in NSScreen.screens {

            let id =
                ObjectIdentifier(screen)

            guard let window =
                windows[id]
            else {
                continue
            }

            window.setFrameOrigin(
                notchOrigin(
                    on:
                        screen,

                    size:
                        canvasSize
                )
            )
        }

        updateAllClickThroughStates()
    }

    // MARK: - Hover Region

    func setHoverActive(
        _ active: Bool,
        for screenID: ObjectIdentifier
    ) {

        // A docked island owns its own top-center hit region.
        if dockedScreens.contains(screenID) {

            updateAllClickThroughStates()

            return
        }

        if active {

            activeScreenID =
                screenID

        } else if activeScreenID == screenID {

            activeScreenID =
                nil
        }

        updateAllClickThroughStates()
    }

    // MARK: - Dock Region

    func setDocked(
        _ docked: Bool,
        for screenID: ObjectIdentifier
    ) {

        if docked {

            dockedScreens.insert(
                screenID
            )

            // Docked islands must be compact.
            if activeScreenID == screenID {

                activeScreenID =
                    nil
            }

        } else {

            dockedScreens.remove(
                screenID
            )
        }

        updateAllClickThroughStates()
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {

        guard localMouseMonitor == nil else {
            return
        }

        localMouseMonitor =
            NSEvent.addLocalMonitorForEvents(
                matching:
                    // `.mouseMoved` alone misses drags entirely — macOS
                    // sends `.leftMouseDragged` instead of `.mouseMoved`
                    // once a button is held down and the cursor moves,
                    // which is exactly the case that matters for
                    // detecting a file being dragged toward the notch.
                    // Without this, `updateAllClickThroughStates()`
                    // simply never runs during a drag, so the window
                    // stays click-through the entire time and the
                    // drag-catch zone never gets a chance to widen.
                    // `.leftMouseUp` is watched too, purely to clear
                    // `lastKnownDragState` promptly the instant a drag
                    // actually ends — see that property's doc comment.
                    [.mouseMoved, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in

                self?.noteDragState(from: event.type)
                self?.scheduleClickThroughUpdate()

                return event
            }

        globalMouseMonitor =
            NSEvent.addGlobalMonitorForEvents(
                matching:
                    [.mouseMoved, .leftMouseDragged, .leftMouseUp]
            ) { [weak self] event in

                self?.noteDragState(from: event.type)
                self?.scheduleClickThroughUpdate()
            }

        // Separate monitor, separate purpose: detects an actual click
        // (not just movement) anywhere outside every screen's expanded
        // rect, to satisfy "clicking anywhere else should collapse the
        // expanded view." Global only — a click that lands inside our
        // OWN window is a legitimate interaction, not an "outside"
        // click, and local monitors only ever see events within our
        // own app anyway.
        globalMouseDownMonitor =
            NSEvent.addGlobalMonitorForEvents(
                matching:
                    [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in

                Task { @MainActor [weak self] in
                    self?.handlePotentialOutsideClick()
                }
            }

        NotificationCenter.default.addObserver(
            self,

            selector:
                #selector(
                    screenParametersChanged
                ),

            name:
                NSApplication
                    .didChangeScreenParametersNotification,

            object:
                nil
        )
    }

    @objc
    private func screenParametersChanged() {

        repositionAllWindows()

        // A screen may have connected/disconnected (e.g. the lid just
        // closed and the built-in display dropped out of
        // `NSScreen.screens` entirely). `repositionAllWindows()` only
        // repositions windows that already exist — it never adds or
        // removes any. `AppDelegate` owns that decision (it knows the
        // user's `NotchDisplayMode`), so just let it know something
        // changed.
        onScreensChanged?()
    }

    // MARK: - Click Through

    /// Coalesces bursts of mouse events into at most one pending
    /// recompute — see `clickThroughUpdateScheduled`'s doc comment.
    private func scheduleClickThroughUpdate() {

        guard !clickThroughUpdateScheduled else {
            return
        }

        clickThroughUpdateScheduled = true

        Task { @MainActor [weak self] in
            self?.clickThroughUpdateScheduled = false
            self?.updateAllClickThroughStates()
        }
    }

    private func updateAllClickThroughStates() {

        let cursor =
            NSEvent.mouseLocation

        for screen in NSScreen.screens {

            let id =
                ObjectIdentifier(screen)

            guard let window =
                windows[id]
            else {
                continue
            }

            let dragCatchRect =
                lastKnownDragState
                    ? dragCatchZoneRect(for: window)
                    : .zero

            // ---------------------------------------------------------
            // DOCKED
            //
            // Keep ONLY the top-center compact hit region active.
            // ---------------------------------------------------------

            if dockedScreens.contains(id) {

                let dockRect =
                    dockedHitRect(
                        for:
                            window
                    )

                let shouldInteract =
                    dockRect.contains(cursor)
                    || dragCatchRect.contains(cursor)

                if window.ignoresMouseEvents == shouldInteract {
                    window.ignoresMouseEvents = !shouldInteract
                }

                continue
            }

            // ---------------------------------------------------------
            // NORMAL
            //
            // FIX: hover area inflating and getting stuck oversized.
            //
            // `IslandRootView`'s own SwiftUI `.onHover` covers its full
            // reported size — the fixed shared canvas (390×225), NOT
            // just the small true compact pill (263×29) sitting inside
            // it. The drag-catch zone widens `ignoresMouseEvents` across
            // a much bigger area (600×90) while dragging, which can give
            // that oversized `.onHover` a chance to fire and set
            // `activeScreenID` from a cursor position nowhere near the
            // true pill. A PREVIOUS fix here only cleared that
            // afterward, once the cursor moved outside the resulting
            // (still-too-large) rect — but if the cursor just stays
            // anywhere within that wider area, which is quite likely
            // near the notch, that check never fires and the hover
            // stays stuck oversized indefinitely.
            //
            // Replaced with something authoritative instead: computed
            // fresh from geometry on every single mouse-move, never
            // trusting whatever `activeScreenID` was set to by anything
            // else beforehand. "Start" hovering requires the cursor to
            // genuinely be inside the small compact rect — never the
            // wider drag-catch or full-canvas areas. Once genuinely
            // started, it's allowed to "stay" expanded as long as the
            // cursor remains inside the resulting larger rect (so
            // moving into the expanded controls to interact with them
            // still works normally) — but it can never be ENTERED any
            // other way. Since this runs every movement, it also
            // instantly overrides any stale/spurious value `setHoverActive`
            // may have set moments earlier, rather than just reacting
            // to it after the fact.
            // ---------------------------------------------------------

            let compactRect =
                activeRectOnScreen(for: window, isExpanded: false)

            let wasAlreadyHoverExpanded =
                activeScreenID == id

            let previouslyExpandedRect =
                wasAlreadyHoverExpanded
                    ? activeRectOnScreen(for: window, isExpanded: true)
                    : .zero

            if compactRect.contains(cursor) {

                activeScreenID = id

            } else if wasAlreadyHoverExpanded,
                      previouslyExpandedRect.contains(cursor) {

                // Stay expanded — cursor is still within the larger
                // "peek" area. `activeScreenID` is already `id`;
                // nothing to change.

            } else if activeScreenID == id,
                      !currentActivityIsForcingExpanded() {

                activeScreenID = nil
            }

            let activeRect =
                activeRectOnScreen(
                    for: window,
                    isExpanded:
                        activeScreenID == id
                        || currentActivityIsForcingExpanded()
                )

            let shouldInteract =
                activeRect.contains(cursor)
                || dragCatchRect.contains(cursor)

            // Guard against writing the same value repeatedly — a real
            // drag can call this dozens of times a second even when
            // nothing has actually changed, and `ignoresMouseEvents`'s
            // setter is a real AppKit property change, not a free no-op.
            // Setting it redundantly at that frequency, layered on top
            // of SwiftUI simultaneously re-laying-out the same content
            // in response to `@Published` changes, is a plausible
            // contributor to the reported layout-recursion warning.
            if window.ignoresMouseEvents == shouldInteract {
                window.ignoresMouseEvents = !shouldInteract
            }
        }
    }

    /// True whenever the currently-owned activity is rendering itself
    /// expanded for a reason that ISN'T plain SwiftUI hover — which
    /// `activeScreenID` has no way to know about, since it's only ever
    /// set from `IslandRootView`'s `.onHover`. Two real bugs came from
    /// that gap, both now covered here:
    ///
    /// 1. The drag-choice panel disappearing mid-drag. SwiftUI's
    ///    `.onHover` simply never fires during an actual OS-level drag
    ///    session — hover tracking and drag tracking are separate event
    ///    paths in AppKit — so `activeScreenID` stayed nil the entire
    ///    time, `activeRect` stayed compact-sized, and the moment the
    ///    panel visually grew past that (immediately — it's taller than
    ///    the drag-catch strip), the cursor fell outside every
    ///    interactive region and the OS treated that as the drag having
    ///    left our destination.
    /// 2. The shelf's post-drop reveal being unclickable if the user
    ///    isn't already hovering when it appears — `isShowingFreshReveal`
    ///    forces the VIEW to render expanded regardless of hover, but
    ///    without this, the click-through hit region had no idea and
    ///    stayed compact-sized, so the visually-expanded panel's own
    ///    delete buttons / drag-out targets weren't actually clickable.
    var currentActivityIsForcingExpanded: () -> Bool = { false }

    // MARK: - Click Outside

    /// Checked on every real click (not just movement) — per direct
    /// request: clicking anywhere else on screen should collapse the
    /// expanded island. Only acts if something is actually currently
    /// expanded somewhere; a random click while everything's compact is
    /// a no-op, not a broadcast.
    private func handlePotentialOutsideClick() {

        guard
            activeScreenID != nil
            || currentActivityIsForcingExpanded()
        else {
            return
        }

        let cursor =
            NSEvent.mouseLocation

        for screen in NSScreen.screens {

            let id =
                ObjectIdentifier(screen)

            guard let window =
                windows[id]
            else {
                continue
            }

            let expandedRect =
                activeRectOnScreen(
                    for: window,
                    isExpanded: true
                )

            if expandedRect.contains(cursor) {
                // The click landed inside an island's own expanded
                // rect — that's an interaction WITH it, not a click
                // "elsewhere."
                return
            }
        }

        NotificationCenter.default.post(
            name: .islandRequestCollapse,
            object: nil
        )

        onOutsideClickWhileFileDropExpanded?()
    }

    /// Separate from the `NotificationCenter` broadcast above —
    /// `FileDropActivity` isn't a SwiftUI view, so it can't subscribe to
    /// `.onReceive` the way `IslandRootView` does. `AppDelegate` wires
    /// this directly to cancel `isDragHovering`/`isShowingFreshReveal`.
    var onOutsideClickWhileFileDropExpanded: (() -> Void)?

    // MARK: - Drag Catch Zone

    /// A generous, always-centered strip at the top of the screen —
    /// independent of, and much wider than, `activeRect` — that exists
    /// purely so a system-wide file drag can be detected before the
    /// user has precisely targeted the (much smaller) visible pill.
    private func dragCatchZoneRect(
        for window: NSWindow
    ) -> NSRect {

        let size =
            CGSize(
                width: DesignTokens.FileDropMetrics.dragCatchZoneWidth,
                height: DesignTokens.FileDropMetrics.dragCatchZoneHeight
            )

        let originInCanvas =
            CGPoint(
                x: (canvasSize.width - size.width) / 2,
                y: 0
            )

        let screenX =
            window.frame.origin.x + originInCanvas.x

        let screenY =
            window.frame.origin.y
            + (canvasSize.height - originInCanvas.y - size.height)

        return NSRect(
            x: screenX,
            y: screenY,
            width: size.width,
            height: size.height
        )
    }

    // MARK: - Active Rect

    private func activeRectOnScreen(
        for window: NSWindow,
        isExpanded: Bool
    ) -> NSRect {

        let size =
            isExpanded
                ? expandedSize
                : compactSize

        // MusicIslandView is hosted inside the padded canvas.
        // The visible Island therefore starts at canvasInsetX.
        let originInCanvas =
            CGPoint(
                x:
                    DesignTokens.Shadow.canvasInsetX
                    + (
                        canvasSize.width
                        - DesignTokens.Shadow.canvasInsetX * 2
                        - size.width
                    ) / 2,

                y:
                    0
            )

        let screenX =
            window.frame.origin.x
            + originInCanvas.x

        let screenY =
            window.frame.origin.y
            + (
                canvasSize.height
                - originInCanvas.y
                - size.height
            )

        // Give the compact Island a small invisible buffer so touching
        // anywhere on the visible pill immediately triggers hover.
        let horizontalPadding:
            CGFloat =
                isExpanded
                    ? 0
                    : 2

        let verticalPadding:
            CGFloat =
                isExpanded
                    ? 0
                    : 2

        return NSRect(
            x:
                screenX
                - horizontalPadding,

            y:
                screenY
                - verticalPadding,

            width:
                size.width
                + horizontalPadding * 2,

            height:
                size.height
                + verticalPadding * 2
        )
    }
    // MARK: - Docked Hit Rect

    private func dockedHitRect(
        for window: NSWindow
    ) -> NSRect {

        // The docked target is the same top-center logical location
        // as the compact island.
        //
        // This means:
        //
        // Mac WITH notch:
        //     target sits directly below/within the notch area.
        //
        // Mac WITHOUT notch:
        //     target becomes a virtual notch at the screen center.
        //
        // No hardware-specific coordinates are required.

        let targetWidth =
            compactSize.width

        let targetHeight =
            compactSize.height

        let originInCanvas =
            CGPoint(
                x:
                    (
                        canvasSize.width
                        - targetWidth
                    )
                    / 2,

                y:
                    0
            )

        let screenX =
            window.frame.origin.x
            + originInCanvas.x

        let screenY =
            window.frame.origin.y
            + (
                canvasSize.height
                - originInCanvas.y
                - targetHeight
            )

        // The compact hover/click region should match the
        // visible compact island exactly: 263 × 29.
        // Do not add padding here — this rectangle is what
        // AppKit uses before SwiftUI receives the hover event.

        let horizontalPadding: CGFloat = 0
        let verticalPadding: CGFloat = 4

        return NSRect(
            x:
                screenX
                - horizontalPadding,

            y:
                screenY
                - verticalPadding,

            width:
                targetWidth
                + horizontalPadding * 2,

            height:
                targetHeight
                + verticalPadding * 2
        )
    }

    // MARK: - Position

    private func notchOrigin(
        on screen: NSScreen,
        size: CGSize
    ) -> NSPoint {

        let frame =
            screen.frame

        let x =
            (
                frame.midX
                - size.width / 2
            )
            .rounded()

        let y =
            (
                frame.maxY
                - size.height
            )
            .rounded()

        return NSPoint(
            x:
                x,

            y:
                y
        )
    }

    // MARK: - Cleanup

    deinit {

        if let localMouseMonitor {

            NSEvent.removeMonitor(
                localMouseMonitor
            )
        }

        if let globalMouseMonitor {

            NSEvent.removeMonitor(
                globalMouseMonitor
            )
        }

        NotificationCenter.default.removeObserver(
            self
        )
    }
}
