import AppKit

/// The small menu-bar dropdown every notch app has. Lets the user pick
/// which screen(s) the Island appears on (`NotchDisplayMode`), and quit
/// the app — this is an accessory app with no Dock icon, so this menu is
/// the only way to quit it.
@MainActor
final class MenuBarController: NSObject {

    private let statusItem =
        NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    /// Whether the menu bar icon is shown. Driven from
    /// `AppDelegate.reconcileIslands()` (external display connected, or
    /// the "Always show menu bar icon" setting).
    var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    /// Opens the Settings window (see `SettingsWindowController`).
    static func openSettings() {
        SettingsWindowController.shared.show()
    }

    /// Fired after the user picks a different display mode, so
    /// `AppDelegate` can reconcile which screens currently have an
    /// Island window.
    var onDisplayModeChanged: (() -> Void)?

    override init() {
        super.init()

        if let button = statusItem.button {
            button.image = Self.makeIcon()
        }

        statusItem.menu = buildMenu()
    }

    /// A screen with a notch hanging from its top edge — what ARC is. Drawn
    /// as a template image, so macOS tints it for light and dark menu bars.
    private static func makeIcon() -> NSImage {

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in

            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            context.setStrokeColor(NSColor.black.cgColor)
            context.setFillColor(NSColor.black.cgColor)

            // Screen outline.
            context.setLineWidth(1.3)
            context.addPath(
                CGPath(
                    roundedRect: CGRect(x: 1.8, y: 3.8, width: 14.4, height: 10.4),
                    cornerWidth: 2.4,
                    cornerHeight: 2.4,
                    transform: nil
                )
            )
            context.strokePath()

            // The notch: flat top, flared top corners, rounded bottom.
            let left: CGFloat = 6.2, right: CGFloat = 11.8
            let top: CGFloat = 3.6, bottom: CGFloat = 7.6
            let flare: CGFloat = 1.0, radius: CGFloat = 1.2

            let notch = CGMutablePath()
            notch.move(to: CGPoint(x: left - flare, y: top))
            notch.addQuadCurve(
                to: CGPoint(x: left, y: top + flare),
                control: CGPoint(x: left, y: top)
            )
            notch.addLine(to: CGPoint(x: left, y: bottom - radius))
            notch.addQuadCurve(
                to: CGPoint(x: left + radius, y: bottom),
                control: CGPoint(x: left, y: bottom)
            )
            notch.addLine(to: CGPoint(x: right - radius, y: bottom))
            notch.addQuadCurve(
                to: CGPoint(x: right, y: bottom - radius),
                control: CGPoint(x: right, y: bottom)
            )
            notch.addLine(to: CGPoint(x: right, y: top + flare))
            notch.addQuadCurve(
                to: CGPoint(x: right + flare, y: top),
                control: CGPoint(x: right, y: top)
            )
            notch.closeSubpath()

            context.addPath(notch)
            context.fillPath()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = "ARC"

        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        for mode in NotchDisplayMode.allCases {
            let item = NSMenuItem(
                title: mode.menuTitle,
                action: #selector(selectDisplayMode(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = mode
            item.state = (mode == NotchDisplayMode.current) ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let timerItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()

        for preset in TimerPreset.all {
            let item = NSMenuItem(
                title: preset.title,
                action: #selector(startTimer(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = preset.seconds
            timerMenu.addItem(item)
        }

        timerItem.submenu = timerMenu
        menu.addItem(timerItem)

        let stopwatchItem = NSMenuItem(
            title: "Start Stopwatch",
            action: #selector(startStopwatch),
            keyEquivalent: ""
        )
        stopwatchItem.target = self
        menu.addItem(stopwatchItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(UpdateController.checkForUpdates),
            keyEquivalent: ""
        )
        updatesItem.target = UpdateController.shared
        menu.addItem(updatesItem)

        menu.addItem(.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return menu
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        guard let seconds = sender.representedObject as? TimeInterval else { return }
        TimerPreset.start(seconds)
    }

    @objc private func startStopwatch() {
        TimerPreset.start(nil)
    }

    @objc private func openSettings() {
        Self.openSettings()
    }

    @objc private func selectDisplayMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? NotchDisplayMode else {
            return
        }

        NotchDisplayMode.current = mode

        for item in sender.menu?.items ?? [] {
            item.state = (item.representedObject as? NotchDisplayMode) == mode ? .on : .off
        }

        onDisplayModeChanged?()
    }
}
