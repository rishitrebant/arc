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

    private var menuBarController:
        MenuBarController!

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

        menuBarController =
            MenuBarController()

        menuBarController.onDisplayModeChanged =
            { [weak self] in

                self?.reconcileIslands()
            }

        windowManager.onScreensChanged =
            { [weak self] in

                self?.reconcileIslands()
            }

        reconcileIslands()
    }

    // MARK: - Screen Selection

    private var builtInScreen: NSScreen? {

        NSScreen.screens.first { screen in

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
    }

    private var externalScreens: [NSScreen] {

        let builtInID =
            builtInScreen.map(
                ObjectIdentifier.init
            )

        return NSScreen.screens.filter { screen in

            ObjectIdentifier(screen)
                != builtInID
        }
    }

    /// Which physical screens should currently have an Island window,
    /// per the user's `NotchDisplayMode` selection and whatever's
    /// actually connected right now. A screen the user wants but that
    /// isn't connected (e.g. `.externalOnly` with no external monitor
    /// attached) simply contributes nothing — no window, no crash.
    private func screensForCurrentMode() -> [NSScreen] {

        switch NotchDisplayMode.current {

        case .macBookOnly:

            return builtInScreen.map { [$0] }
                ?? []

        case .externalOnly:

            return externalScreens

        case .both:

            return (
                builtInScreen.map { [$0] }
                    ?? []
            )
                + externalScreens
        }
    }

    // MARK: - Reconcile

    /// Adds/removes Island windows so they exactly match
    /// `screensForCurrentMode()`. Called at launch, whenever the user
    /// changes `NotchDisplayMode` from the menu bar, and whenever macOS
    /// reports a screen configuration change (monitor connected/
    /// disconnected, lid closed/opened in clamshell mode, resolution
    /// change).
    ///
    /// Deliberately diffs against a freshly computed desired set every
    /// time, rather than trying to match old screens to new ones —
    /// macOS can recreate `NSScreen` objects wholesale on a
    /// reconfiguration, which would make stale `ObjectIdentifier`s
    /// unreliable to compare directly. Anything not in the fresh
    /// desired set gets torn down; anything in it that's missing gets
    /// created. This is what actually fixes "the Island jumps to my
    /// external monitor after closing the lid": previously, nothing
    /// ever removed the window that used to belong to the (now
    /// disconnected) built-in screen, so it just sat at its last known
    /// coordinates — coordinates that can end up overlapping the
    /// remaining external display once macOS recomputes the shared
    /// screen coordinate space, and macOS's own "don't strand a window
    /// fully offscreen" behavior was doing the rest.
    private func reconcileIslands() {

        let desiredScreens =
            screensForCurrentMode()

        let desiredIDs =
            Set(
                desiredScreens.map(
                    ObjectIdentifier.init
                )
            )

        for existingID in windowManager.presentedScreenIDs
        where !desiredIDs.contains(existingID) {

            windowManager.removeWindow(
                for: existingID
            )
        }

        for screen in desiredScreens {

            let id =
                ObjectIdentifier(screen)

            guard !windowManager.presentedScreenIDs.contains(id)
            else {
                continue
            }

            presentIsland(
                on: screen
            )
        }
    }

    private func presentIsland(
        on screen: NSScreen
    ) {

        let screenID =
            ObjectIdentifier(
                screen
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
                screen
        )
    }
}
