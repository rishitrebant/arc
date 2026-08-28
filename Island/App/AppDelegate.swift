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

        createIslandOnMacBookScreen()
    }

    private func createIslandOnMacBookScreen() {

        guard let macBookScreen =
            NSScreen.screens.first(
                where: { screen in

                    guard let screenNumber =
                        screen.deviceDescription[
                            NSDeviceDescriptionKey(
                                "NSScreenNumber"
                            )
                        ] as? CGDirectDisplayID

                    else {
                        return false
                    }

                    return CGDisplayIsBuiltin(
                        screenNumber
                    ) != 0
                }
            )

        else {
            return
        }

        let screenID =
            ObjectIdentifier(
                macBookScreen
            )

        let root =
            IslandRootView(
                activityManager:
                    activityManager,

                screenID:
                    screenID,

                onHoverRegionChange:
                    { [weak windowManager]
                        active,
                        screenID in

                        windowManager?.setHoverActive(
                            active,
                            for:
                                screenID
                        )
                    },

                onDockStateChange:
                    { [weak windowManager]
                        docked,
                        screenID in

                        windowManager?.setDocked(
                            docked,
                            for:
                                screenID
                        )
                    }
            )

        windowManager.present(
            root,
            for:
                macBookScreen
        )
    }
}
