import AppKit

/// The small menu-bar dropdown every notch app has. Lets the user pick
/// which screen(s) the Island appears on (`NotchDisplayMode`), and quit
/// the app — this is an accessory app with no Dock icon, so this menu is
/// the only way to quit it.
@MainActor
final class MenuBarController: NSObject {

    private let statusItem =
        NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    /// Fired after the user picks a different display mode, so
    /// `AppDelegate` can reconcile which screens currently have an
    /// Island window.
    var onDisplayModeChanged: (() -> Void)?

    override init() {
        super.init()

        if let button = statusItem.button {
            let image = NSImage(
                systemSymbolName: "macwindow",
                accessibilityDescription: "Island"
            )
            image?.isTemplate = true
            button.image = image
        }

        statusItem.menu = buildMenu()
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

        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        return menu
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
