import AppKit
import SwiftUI

/// Application lifecycle + composition root.
///
/// Requires `LSUIElement = YES` in Info.plist (Target > Info > "Application
/// is agent (UIElement)") so the app runs with no Dock icon and no menu
/// bar — per Window Behaviour: "This should never look or feel like a
/// normal Mac app."
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let activityManager = ActivityManager()
    private let windowManager = WindowManager()

    // Retained here since ActivityManager only stores type-erased boxes —
    // the concrete activity needs a strong owner somewhere in the app.
    private var musicActivity: MusicActivity!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // belt-and-suspenders alongside LSUIElement

        musicActivity = MusicActivity()
        activityManager.register(musicActivity)

        let root = IslandRootView(
            activityManager: activityManager,
            onSizeChange: { [weak windowManager] size in
                windowManager?.resize(to: size)
            }
        )
        windowManager.present(root)
    }
}
