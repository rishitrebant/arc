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

    private var compactSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.compactWidth,
            height: DesignTokens.MusicMetrics.compactHeight
        )
    }

    private var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.expandedWidth,
            height: DesignTokens.MusicMetrics.expandedHeight
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
                on: screen,
                size: canvasSize
            )

        let panel =
            windows[screenID]
            ?? IslandWindow(
                contentRect:
                    NSRect(
                        origin: origin,
                        size: canvasSize
                    )
            )

        let centeredRoot =
            rootView
                .padding(
                    EdgeInsets(
                        top: 0,

                        leading:
                            DesignTokens.Shadow.canvasInsetX,

                        bottom:
                            DesignTokens.Shadow.canvasInsetBottom,

                        trailing:
                            DesignTokens.Shadow.canvasInsetX
                    )
                )
                .frame(
                    width: canvasSize.width,
                    height: canvasSize.height,
                    alignment: .top
                )

        let hosting =
            NSHostingView(
                rootView: centeredRoot
            )

        hosting.frame =
            NSRect(
                origin: .zero,
                size: canvasSize
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

        activeScreenID =
            nil
    }

    func repositionAllWindows() {

        for screen in NSScreen.screens {

            let id =
                ObjectIdentifier(screen)

            guard
                let window =
                    windows[id]
            else {
                continue
            }

            window.setFrameOrigin(
                notchOrigin(
                    on: screen,
                    size: canvasSize
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

        if active {

            activeScreenID =
                screenID

        } else if
            activeScreenID ==
                screenID
        {

            activeScreenID =
                nil
        }

        updateAllClickThroughStates()
    }

    // MARK: - Mouse Tracking

    private func startMouseTracking() {

        guard
            localMouseMonitor == nil
        else {
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

            guard
                let window =
                    windows[id]
            else {
                continue
            }

            let activeRect =
                activeRectOnScreen(
                    for: window,

                    isExpanded:
                        activeScreenID == id
                )

            window.ignoresMouseEvents =
                !activeRect.contains(cursor)
        }
    }

    private func activeRectOnScreen(
        for window: NSWindow,
        isExpanded: Bool
    ) -> NSRect {

        let size =
            isExpanded
                ? expandedSize
                : compactSize

        // ---------------------------------------------------------
        // IMPORTANT:
        //
        // The SwiftUI content is NOT centered inside the canvas.
        //
        // `present()` adds:
        //
        //     leading: canvasInsetX
        //
        // and the same inset on the trailing side.
        //
        // Therefore the actual island begins at canvasInsetX.
        // ---------------------------------------------------------

        let originInCanvas =
            CGPoint(
                x:
                    DesignTokens.Shadow.canvasInsetX,

                y:
                    0
            )

        let screenX =
            window.frame.origin.x
            + originInCanvas.x

        let screenY =
            window.frame.origin.y
            + canvasSize.height
            - size.height

        // ---------------------------------------------------------
        // COMPACT HIT AREA
        //
        // The visible island is 29pt high, but its album/waveform
        // content needs a little breathing room for hover detection.
        //
        // This ONLY changes the mouse hit area.
        //
        // It does NOT change the visual island size.
        // ---------------------------------------------------------

        if !isExpanded {

            let hitHeight:
                CGFloat = 34

            let visualCenterY =
                screenY
                + size.height / 2

            return NSRect(
                x:
                    screenX,

                y:
                    visualCenterY
                    - hitHeight / 2,

                width:
                    size.width,

                height:
                    hitHeight
            )
        }

        // ---------------------------------------------------------
        // EXPANDED HIT AREA
        // ---------------------------------------------------------

        return NSRect(
            x:
                screenX,

            y:
                screenY,

            width:
                size.width,

            height:
                size.height
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
            x: x,
            y: y
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
