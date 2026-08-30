import AppKit
import SwiftUI

@MainActor
final class WindowManager {

    private var windows:
        [ObjectIdentifier: IslandWindow] = [:]

    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private var activeScreenID:
        ObjectIdentifier?

    /// Screens whose island is currently docked.
    ///
    /// The window remains alive, but its visible island is hidden.
    /// We keep a small hit region at the top-center so the user can
    /// click or drag downward to restore it.
    private var dockedScreens:
        Set<ObjectIdentifier> = []

    private var compactSize: CGSize {

        CGSize(
            width:
                DesignTokens.MusicMetrics.compactWidth,

            height:
                DesignTokens.MusicMetrics.compactHeight
        )
    }

    private var expandedSize: CGSize {

        CGSize(
            width:
                DesignTokens.MusicMetrics.expandedWidth,

            height:
                DesignTokens.MusicMetrics.expandedHeight
        )
    }

    private var canvasSize: CGSize {

        CGSize(
            width:
                expandedSize.width
                + DesignTokens.Shadow.canvasInsetX * 2,

            height:
                expandedSize.height
                + DesignTokens.Shadow.canvasInsetBottom
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

    func removeAllWindows() {

        for window in windows.values {

            window.orderOut(nil)
        }

        windows.removeAll()

        dockedScreens.removeAll()

        activeScreenID =
            nil
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
                    [.mouseMoved]
            ) { [weak self] event in

                Task { @MainActor in

                    self?
                        .updateAllClickThroughStates()
                }

                return event
            }

        globalMouseMonitor =
            NSEvent.addGlobalMonitorForEvents(
                matching:
                    [.mouseMoved]
            ) { [weak self] _ in

                Task { @MainActor in

                    self?
                        .updateAllClickThroughStates()
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
    }

    // MARK: - Click Through

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

                window.ignoresMouseEvents =
                    !dockRect.contains(
                        cursor
                    )

                continue
            }

            // ---------------------------------------------------------
            // NORMAL
            // ---------------------------------------------------------

            let activeRect =
                activeRectOnScreen(
                    for:
                        window,

                    isExpanded:
                        activeScreenID == id
                )

            window.ignoresMouseEvents =
                !activeRect.contains(
                    cursor
                )
        }
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

        // Slightly larger hit area than the invisible island.
        //
        // This makes the dock much easier to grab without making
        // the entire window clickable.
        let horizontalPadding:
            CGFloat = 12

        let verticalPadding:
            CGFloat = 6

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
