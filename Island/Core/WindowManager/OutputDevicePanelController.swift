import AppKit
import SwiftUI

/// Owns the output-device panel independently from the Island's SwiftUI
/// hierarchy. This avoids NSPopover's automatic repositioning/dismissal
/// fighting the Island's hover/compact state.
@MainActor
final class OutputDevicePanelController {

    static let shared = OutputDevicePanelController()

    private var panel: NSPanel?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private init() {}

    // MARK: - Presentation

    func present(
        manager: AudioOutputDeviceManager
    ) {

        dismiss(
            sendNotification: false
        )

        let panel = NSPanel(
            contentRect:
                NSRect(
                    x: 0,
                    y: 0,
                    width: 290,
                    height: 260
                ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.level = .statusBar + 2
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]

        let picker = AudioOutputPicker(
            manager: manager,
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let hosting = NSHostingView(
            rootView: picker
        )

        hosting.frame = panel.contentRect(forFrameRect: panel.frame)
        hosting.autoresizingMask = [
            .width,
            .height
        ]

        panel.contentView = hosting

        let panelSize = NSSize(
            width: 290,
            height: max(
                118,
                min(
                    310,
                    86 + CGFloat(manager.devices.count) * 61
                )
            )
        )

        panel.setContentSize(panelSize)

        positionPanel(
            panel,
            size: panelSize
        )

        self.panel = panel

        installMouseMonitors()

        panel.orderFrontRegardless()

        NotificationCenter.default.post(
            name: .islandOutputPickerWillPresent,
            object: nil
        )
    }

    func dismiss(
        sendNotification: Bool = true
    ) {

        guard panel != nil else {
            removeMouseMonitors()
            return
        }

        panel?.orderOut(nil)
        panel = nil

        removeMouseMonitors()

        if sendNotification {
            NotificationCenter.default.post(
                name: .islandOutputPickerDidDismiss,
                object: nil
            )
        }
    }

    // MARK: - Position

    private func positionPanel(
        _ panel: NSPanel,
        size: NSSize
    ) {

        let mouse = NSEvent.mouseLocation

        let screen =
            NSScreen.screens.first {
                $0.frame.contains(mouse)
            }
            ?? NSScreen.main

        guard let screen else {
            panel.setFrameOrigin(mouse)
            return
        }

        let visible = screen.visibleFrame

        // Prefer the right side of the AirPlay button.
        var x = mouse.x + 22

        // Put the panel below the clicked button.
        var y = mouse.y - size.height - 16

        // Keep it on-screen while preserving the right-side placement
        // whenever the display has enough space.
        if x + size.width > visible.maxX - 10 {
            x = visible.maxX - size.width - 10
        }

        if x < visible.minX + 10 {
            x = visible.minX + 10
        }

        if y < visible.minY + 10 {
            y = visible.minY + 10
        }

        if y + size.height > visible.maxY - 10 {
            y = visible.maxY - size.height - 10
        }

        panel.setFrameOrigin(
            NSPoint(
                x: x,
                y: y
            )
        )
    }

    // MARK: - Outside Click

    private func installMouseMonitors() {

        removeMouseMonitors()

        globalMouseMonitor =
            NSEvent.addGlobalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak self] _ in

                Task { @MainActor [weak self] in
                    self?.handleGlobalClick()
                }
            }

        localMouseMonitor =
            NSEvent.addLocalMonitorForEvents(
                matching: .leftMouseDown
            ) { [weak self] event in

                guard let self else {
                    return event
                }

                let location =
                    NSEvent.mouseLocation

                if self.isInsidePanel(
                    location
                ) {
                    return event
                }

                if self.isInsideIsland(
                    location
                ) {
                    return event
                }

                self.dismiss()

                return event
            }
    }

    private func handleGlobalClick() {

        let location =
            NSEvent.mouseLocation

        if isInsidePanel(location) {
            return
        }

        if isInsideIsland(location) {
            return
        }

        dismiss()
    }

    private func removeMouseMonitors() {

        if let monitor = localMouseMonitor {
            NSEvent.removeMonitor(monitor)
            localMouseMonitor = nil
        }

        if let monitor = globalMouseMonitor {
            NSEvent.removeMonitor(monitor)
            globalMouseMonitor = nil
        }
    }

    // MARK: - Hit Testing

    private func isInsidePanel(
        _ point: NSPoint
    ) -> Bool {

        panel?.frame.contains(point) ?? false
    }

    private func isInsideIsland(
        _ point: NSPoint
    ) -> Bool {

        for window in NSApp.windows {

            guard
                let islandWindow =
                    window as? IslandWindow,
                islandWindow.isVisible
            else {
                continue
            }

            let canvasInsetX =
                DesignTokens.Shadow.canvasInsetX

            let expandedWidth =
                DesignTokens.MusicMetrics.expandedWidth

            let expandedHeight =
                DesignTokens.MusicMetrics.expandedHeight

            // The actual Island sits at the top of the hosting canvas.
            let rect = NSRect(
                x:
                    islandWindow.frame.minX
                    + canvasInsetX,

                y:
                    islandWindow.frame.maxY
                    - expandedHeight,

                width:
                    expandedWidth,

                height:
                    expandedHeight
            )

            if rect.contains(point) {
                return true
            }
        }

        return false
    }
}
