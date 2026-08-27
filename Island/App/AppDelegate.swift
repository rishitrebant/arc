import AppKit
import SwiftUI

@MainActor
final class AppDelegate:
    NSObject,
    NSApplicationDelegate {

    private let activityManager =
        ActivityManager()

    private let windowManager =
        WindowManager()

    private var musicActivity:
        MusicActivity!

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        NSApp.setActivationPolicy(
            .accessory
        )

        musicActivity =
            MusicActivity()

        activityManager.register(
            musicActivity
        )

        createIslandsForAllScreens()
    }

    private func createIslandsForAllScreens() {

        for screen in NSScreen.screens {

            let screenID =
                ObjectIdentifier(screen)

            let root =
                IslandRootView(
                    activityManager:
                        activityManager,

                    screenID:
                        screenID,

                    onHoverRegionChange:
                        { [weak windowManager] active, screenID in

                            windowManager?.setHoverActive(
                                active,
                                for: screenID
                            )
                        }
                )

            windowManager.present(
                root,
                for: screen
            )
        }
    }
}
