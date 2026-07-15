import SwiftUI

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The real UI lives in a manually-managed IslandWindow (see
        // WindowManager), not in a normal SwiftUI Scene — a Scene would
        // give us a standard app window, dock icon, and menu bar, none of
        // which this app wants (per Window Behaviour in PRODUCT.md).
        // `Settings` is the smallest Scene type that satisfies SwiftUI's
        // requirement for at least one Scene without creating a visible window.
        Settings {
            EmptyView()
        }
    }
}
