import AppKit
import SwiftUI
import Combine

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

    private var chargingActivity:
        ChargingActivity!

    private var lowBatteryActivity:
        LowBatteryActivity!

    private var bluetoothActivity:
        BluetoothActivity!

    private var timerActivity:
        TimerActivity!

    private var launcherActivity:
        LauncherActivity!

    private var calendarActivity:
        CalendarActivity!

    private var audioOutputActivity:
        AudioOutputActivity!

    private var youtubeActivity:
        YouTubeActivity!

    private var focusActivity:
        FocusActivity!

    private var cancellables:
        Set<AnyCancellable> = []

    private let hotKeys =
        HotKeyManager()

    private let pasteMonitor =
        PasteMonitor()

    private var dockObserver:
        Task<Void, Never>?

    private var privacyActivity:
        PrivacyActivity!

    private var downloadsActivity:
        DownloadsActivity!

    private var waterActivity: WaterActivity!

    private var volumeActivity: VolumeActivity!
    private var cleaningActivity: CleaningActivity!
    private var nextUpActivity: NextUpActivity!

    private var noteActivity:
        NoteActivity!

    private var capsLockActivity:
        CapsLockActivity!

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

        // The notch of THIS Mac — before anything is laid out from it.
        DesignTokens.NotchMetrics.configure()

        // A regular app: shows in the Dock and the app switcher, and
        // clicking its Dock icon opens Settings (see
        // `applicationShouldHandleReopen`). The island itself is still
        // a borderless overlay window, unaffected by this.
        applyDockPreference()

        Haptics.start()

        // Follow the "Show ARC in the Dock" setting live.
        dockObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            ) {
                self?.applyDockPreference()
            }
        }

        installMainMenu()

        hotKeys.start()
        pasteMonitor.start()

        // First launch: the island only appears when something happens,
        // so open Settings once so there's something to see and the
        // permissions are explained.
        if !UserDefaults.standard.bool(forKey: "hasCompletedFirstLaunch") {

            UserDefaults.standard.set(true, forKey: "hasCompletedFirstLaunch")

            SettingsWindowController.shared.show()
        }

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

        nextUpActivity =
            NextUpActivity(music: musicActivity)

        nextUpActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            nextUpActivity
        )

        youtubeActivity =
            YouTubeActivity()

        youtubeActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            youtubeActivity
        )

        chargingActivity =
            ChargingActivity()

        // Same rule as Music: never auto-close while the cursor is on
        // the island.
        chargingActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            chargingActivity
        )

        lowBatteryActivity =
            LowBatteryActivity()

        lowBatteryActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            lowBatteryActivity
        )

        bluetoothActivity =
            BluetoothActivity()

        lowBatteryActivity.bluetooth = bluetoothActivity

        bluetoothActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            bluetoothActivity
        )

        timerActivity =
            TimerActivity()

        activityManager.register(
            timerActivity
        )

        waterActivity =
            WaterActivity()

        activityManager.register(
            waterActivity
        )

        volumeActivity =
            VolumeActivity()

        volumeActivity.hasActivityOnIsland =
            { [weak self] in

                guard let kind = self?.activityManager.ownedActivity?.kind else { return false }

                return kind != .volume
            }

        activityManager.register(
            volumeActivity
        )

        cleaningActivity =
            CleaningActivity()

        activityManager.register(
            cleaningActivity
        )

        noteActivity =
            NoteActivity()

        activityManager.register(
            noteActivity
        )

        capsLockActivity =
            CapsLockActivity()

        activityManager.register(
            capsLockActivity
        )

        calendarActivity =
            CalendarActivity()

        calendarActivity.requestLowRank =
            { [weak self] low in

                self?.activityManager.setRankOverride(.calendar, low ? 14.5 : nil)
            }

        calendarActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            calendarActivity
        )

        audioOutputActivity =
            AudioOutputActivity()

        audioOutputActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            audioOutputActivity
        )

        focusActivity =
            FocusActivity()

        activityManager.register(
            focusActivity
        )

        privacyActivity =
            PrivacyActivity()

        privacyActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            privacyActivity
        )

        downloadsActivity =
            DownloadsActivity()

        activityManager.register(
            downloadsActivity
        )

        launcherActivity =
            LauncherActivity(
                music: musicActivity,
                bluetooth: bluetoothActivity,
                youtube: youtubeActivity,
                timer: timerActivity
            )

        launcherActivity.water = waterActivity

        launcherActivity.startCleaning =
            { [weak self] in

                self?.cleaningActivity.start() ?? false
            }

        launcherActivity.releaseKeyboard =
            { [weak windowManager] in

                windowManager?.releaseKeyboardFocus()
            }

        launcherActivity.requestElevation =
            { [weak self] elevated in

                self?.activityManager.setElevated(.launcher, elevated)
            }

        launcherActivity.isIslandCurrentlyHovered =
            { [weak windowManager] in

                windowManager?.isAnyScreenCurrentlyHovered ?? false
            }

        activityManager.register(
            launcherActivity
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

                // Two activities sharing the notch: one even pill, and
                // whichever half the cursor is on is the one that expands.
                let compact =
                    self?.activityManager.splitCompactSize
                    ?? owned?.compactSize
                    ?? fallbackCompact

                let expandingActivity =
                    (self?.activityManager.expandsSecondary ?? false)
                        ? (self?.activityManager.secondaryActivity ?? owned)
                        : owned

                return (
                    compact,
                    expandingActivity?.expandedSize ?? fallbackExpanded
                )
            }

        windowManager.currentCompactShift =
            { [weak self] in

                self?.activityManager.ownedActivity?.compactCenterShift ?? 0
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

        // First time ARC opens: the notch glows once, fading in and out.
        if !UserDefaults.standard.bool(forKey: AppSettings.Key.hasSeenIntroGlow) {

            UserDefaults.standard.set(true, forKey: AppSettings.Key.hasSeenIntroGlow)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                NotificationCenter.default.post(name: .islandIntroGlow, object: nil)
            }
        }
    }

    // MARK: - Dock

    /// Shows or hides the Dock icon per Settings. Hidden, ARC is an
    /// accessory app: still running, reachable from the menu bar icon.
    private func applyDockPreference() {

        let policy: NSApplication.ActivationPolicy =
            AppSettings.showDockIcon ? .regular : .accessory

        guard NSApp.activationPolicy() != policy else { return }

        NSApp.setActivationPolicy(policy)

        // Changing policy deactivates the app; bring the Settings window
        // (where the switch was flipped) back to the front.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Clicking the Dock icon (or relaunching from Finder/Spotlight)
    /// opens Settings.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {

        SettingsWindowController.shared.show()

        return false
    }

    /// The island overlay is the app's only other window, so closing
    /// Settings must never quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        false
    }

    /// A minimal menu bar for a Dock app: the app menu with Settings
    /// (⌘,) and Quit (⌘Q), plus the standard Window menu.
    private func installMainMenu() {

        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appItem.submenu = appMenu

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsFromMenu),
            keyEquivalent: ","
        )
        settings.target = self
        appMenu.addItem(settings)

        let updates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(UpdateController.checkForUpdates),
            keyEquivalent: ""
        )
        updates.target = UpdateController.shared
        appMenu.addItem(updates)

        appMenu.addItem(.separator())

        appMenu.addItem(
            NSMenuItem(
                title: "Hide ARC",
                action: #selector(NSApplication.hide(_:)),
                keyEquivalent: "h"
            )
        )

        appMenu.addItem(.separator())

        appMenu.addItem(
            NSMenuItem(
                title: "Quit ARC",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)

        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu

        windowMenu.addItem(
            NSMenuItem(
                title: "Close",
                action: #selector(NSWindow.performClose(_:)),
                keyEquivalent: "w"
            )
        )

        windowMenu.addItem(
            NSMenuItem(
                title: "Minimize",
                action: #selector(NSWindow.performMiniaturize(_:)),
                keyEquivalent: "m"
            )
        )

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
    }

    @objc
    private func openSettingsFromMenu() {
        SettingsWindowController.shared.show()
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
