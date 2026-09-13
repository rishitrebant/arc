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

    private var fileDropActivity:
        FileDropActivity!

    /// Held onto only because `NSSharingServicePicker` doesn't manage
    /// its own lifetime the way a normal Cocoa control does — nothing
    /// else references it once `show(relativeTo:of:preferredEdge:)`
    /// returns, so a local variable would deallocate before the user
    /// gets to interact with it.
    private var activeSharingPicker:
        NSSharingServicePicker?

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {

        NSApp.setActivationPolicy(
            .accessory
        )

        musicActivity =
            MusicActivity()

        // Per direct request: never auto-hide the paused island while
        // the cursor is on it.
        musicActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            musicActivity
        )

        fileDropActivity =
            FileDropActivity()

        fileDropActivity.presentAirDropPicker =
            { [weak self] urls in

                self?.presentAirDropSharingPicker(
                    for: urls
                )
            }

        activityManager.register(
            fileDropActivity
        )

        windowManager.currentContentSize =
            { [weak self] in

                let owned =
                    self?.activityManager.ownedActivity

                let fallbackCompact =
                    CGSize(
                        width: DesignTokens.MusicMetrics.compactWidth,
                        height: DesignTokens.MusicMetrics.compactHeight
                    )

                let fallbackExpanded =
                    CGSize(
                        width: DesignTokens.MusicMetrics.expandedWidth,
                        height: DesignTokens.MusicMetrics.expandedHeight
                    )

                return (
                    owned?.compactSize ?? fallbackCompact,
                    owned?.expandedSize ?? fallbackExpanded
                )
            }

        // Fixes the panel-disappears-mid-drag and unclickable-reveal
        // bugs — see `WindowManager.currentActivityIsForcingExpanded`'s
        // doc comment for the full explanation.
        windowManager.currentActivityIsForcingExpanded =
            { [weak self] in

                guard let self else { return false }

                return self.fileDropActivity.isDragHovering
                    || self.fileDropActivity.isShowingFreshReveal
            }

        // Per direct request: clicking anywhere else on screen should
        // collapse the expanded island. `IslandRootView` handles its
        // own hover-driven `isExpanded` via the `.islandRequestCollapse`
        // notification `WindowManager` posts; `FileDropActivity` isn't
        // a SwiftUI view, so it needs this direct call instead.
        windowManager.onOutsideClickWhileFileDropExpanded =
            { [weak self] in

                self?.fileDropActivity.dismissExpandedState()
            }

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

    private func presentAirDropSharingPicker(
        for urls: [URL]
    ) {

        guard let anchor =
            windowManager.airDropAnchor()
        else {
            return
        }

        let picker =
            NSSharingServicePicker(
                items: urls
            )

        activeSharingPicker =
            picker

        picker.show(
            relativeTo: anchor.rect,
            of: anchor.view,
            preferredEdge: .minY
        )
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

        // `DragCatchLayer` is what actually promotes `fileDropActivity`
        // to ownership in the first place, so it has to exist here,
        // alongside `root`, always — not inside whatever `root` happens
        // to be rendering via `activityManager.ownedActivity` at any
        // given moment (which, before a drag starts, is Music). See
        // `DragCatchLayer`'s own doc comment.
        let combined =
            ZStack(alignment: .top) {

                DragCatchLayer(
                    activity: fileDropActivity
                )

                root
            }

        windowManager.present(
            combined,
            for:
                screen
        )
    }
}
