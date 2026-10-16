import AppKit
import SwiftUI

/// Owns the Settings window: an `NSTabViewController` using the
/// `.toolbar` tab style, which gives the standard preferences look (icon
/// tabs under the title bar, window title = selected tab, window resizes
/// per tab). Built by hand instead of using SwiftUI's `Settings` scene
/// because macOS 14+ refuses to open that scene from AppKit code
/// ("Please use SettingsLink...") — and this app's only entry points are
/// an `NSStatusItem` menu and app relaunch, neither of which can host a
/// `SettingsLink`.
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show() {
        if window == nil {
            window = makeWindow()
        }

        // Accessory apps aren't active by default; without this the
        // window can open behind whatever app is in front.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []

        add(to: tabs, title: "General", symbol: "switch.2", view: GeneralSettingsTab())
        add(to: tabs, title: "Display", symbol: "display", view: DisplaySettingsTab())
        add(to: tabs, title: "Shelf", symbol: "tray.full", view: ShelfSettingsTab())
        add(to: tabs, title: "Music", symbol: "music.note", view: MusicSettingsTab())
        add(to: tabs, title: "About", symbol: "info.circle", view: AboutSettingsTab())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func add<V: View>(
        to tabs: NSTabViewController,
        title: String,
        symbol: String,
        view: V
    ) {
        // Fixed width, height follows the content — the window resizes
        // itself to fit each tab via `preferredContentSize`.
        let host = NSHostingController(rootView: view.frame(width: 520))
        host.sizingOptions = [.preferredContentSize]
        host.title = title

        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}
