import SwiftUI

@main
struct IslandApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The real UI lives in a manually-managed IslandWindow (see
        // WindowManager), not in a normal SwiftUI Scene. `Settings` is
        // the smallest Scene type that satisfies SwiftUI's requirement
        // for at least one Scene without creating a visible window.
        // The real settings window is `SettingsWindowController`.
        Settings {
            EmptyView()
        }
    }
}
