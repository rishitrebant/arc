import AppKit
import SwiftUI

/// Owns the Settings window: an `NSTabViewController` using the
/// `.toolbar` tab style, which gives the standard preferences look (icon
/// tabs under the title bar, window title = selected tab). Built by hand
/// instead of using SwiftUI's `Settings` scene because macOS 14+ refuses
/// to open that scene from AppKit code ("Please use SettingsLink...") —
/// and this app's only entry points are an `NSStatusItem` menu and app
/// relaunch, neither of which can host a `SettingsLink`.
///
/// The window is ONE fixed size for every tab — a tab taller than that
/// scrolls inside it. (It used to resize itself to fit each tab, which
/// grew past the screen as the tabs filled up.) It can be minimised.
@MainActor
final class SettingsWindowController {

    static let shared = SettingsWindowController()

    private var window: NSWindow?

    private static let contentWidth: CGFloat = 620
    private static let preferredContentHeight: CGFloat = 520

    /// The content height, never more than the screen can show.
    private static var contentHeight: CGFloat {

        let available = (NSScreen.main ?? NSScreen.screens.first)?
            .visibleFrame.height ?? preferredContentHeight

        // Leave room for the title bar, the toolbar and a little air.
        return min(preferredContentHeight, max(320, available - 180))
    }

    func show() {
        if window == nil {
            window = makeWindow()
        }

        // The window may be minimised to the Dock — bring it back.
        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }

        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {

        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []

        add(to: tabs, title: "General", symbol: "gearshape", view: GeneralSettingsTab())
        add(to: tabs, title: "Display", symbol: "display", view: DisplaySettingsTab())
        add(to: tabs, title: "Media", symbol: "play.circle", view: MediaSettingsTab())
        add(to: tabs, title: "Timers", symbol: "timer", view: TimerSettingsTab())
        add(to: tabs, title: "Devices", symbol: "headphones", view: DevicesSettingsTab())
        add(to: tabs, title: "Alerts", symbol: "bell.badge", view: AlertsSettingsTab())
        add(to: tabs, title: "Shelf", symbol: "tray.full", view: ShelfSettingsTab())
        add(to: tabs, title: "About", symbol: "info.circle", view: AboutSettingsTab())

        let window = NSWindow(contentViewController: tabs)

        // Minimise added; still not resizable — the size is fixed.
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.setContentSize(
            NSSize(width: Self.contentWidth, height: Self.contentHeight)
        )
        window.center()

        return window
    }

    private func add<V: View>(
        to tabs: NSTabViewController,
        title: String,
        symbol: String,
        view: V
    ) {
        // Every tab is exactly the window's content size; a long one
        // scrolls inside it instead of growing the window.
        let host = NSHostingController(
            rootView: view.frame(
                width: Self.contentWidth,
                height: Self.contentHeight
            )
        )
        host.sizingOptions = []
        host.title = title

        let item = NSTabViewItem(viewController: host)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }
}
