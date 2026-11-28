import AppKit
import Carbon.HIToolbox

extension Notification.Name {
    /// Opens the launcher if it's closed, closes it if it's open.
    static let islandToggleLauncher = Notification.Name("IslandToggleLauncher")

    /// Plays the notch glow's one-off first-launch fade.
    static let islandIntroGlow = Notification.Name("IslandIntroGlow")

    /// Opens the launcher on its clipboard page.
    static let islandOpenClipboard = Notification.Name("IslandOpenClipboard")

    /// Opens the launcher on its notes page, ready for a new note.
    static let islandOpenNotes = Notification.Name("IslandOpenNotes")

    /// Pins the newest note to the notch, or unpins the pinned one.
    static let islandTogglePinnedNote = Notification.Name("IslandTogglePinnedNote")

    /// Opens whatever now owns the island to its expanded card.
    static let islandExpandNow = Notification.Name("IslandExpandNow")

    /// The launcher's panel changed height (page change, a clock started).
    static let islandLauncherLayoutChanged = Notification.Name("IslandLauncherLayoutChanged")

    /// Starts the stopwatch if it isn't running, stops it if it is.
    static let islandToggleStopwatch = Notification.Name("IslandToggleStopwatch")
}

/// System-wide keyboard shortcuts.
///
/// Uses Carbon's `RegisterEventHotKey`, which — unlike a global key
/// monitor — needs NO Accessibility or Input Monitoring permission and
/// works while any app is in front.
///
/// | Shortcut | Action |
/// |----------|--------|
/// | ⌃⌥Space  | open / close the launcher |
/// | ⌃⌥T      | start a timer (the last length you used) |
/// | ⌃⌥S      | start / stop the stopwatch |
/// | ⌃⌥P      | start a 25/5 pomodoro |
/// | ⌥V       | open the clipboard |
/// | ⌃⌥N      | write a quick note |
/// | ⌃⌥U      | pin / unpin a note |
@MainActor
final class HotKeyManager {

    private struct Binding {
        let keyCode: Int
        var modifiers = HotKeyManager.modifiers
        let action: @MainActor () -> Void
    }

    private static let modifiers = UInt32(controlKey | optionKey)

    private static let bindings: [UInt32: Binding] = [
        1: Binding(keyCode: kVK_Space) {
            NotificationCenter.default.post(name: .islandToggleLauncher, object: nil)
        },
        2: Binding(keyCode: kVK_ANSI_T) {
            TimerPreset.start(TimeInterval(AppSettings.lastTimerMinutes * 60))
        },
        3: Binding(keyCode: kVK_ANSI_S) {
            NotificationCenter.default.post(name: .islandToggleStopwatch, object: nil)
        },
        4: Binding(keyCode: kVK_ANSI_P) {
            TimerPreset.startPomodoro(focus: 25 * 60, rest: 5 * 60)
        },
        5: Binding(keyCode: kVK_ANSI_V, modifiers: UInt32(optionKey)) {
            NotificationCenter.default.post(name: .islandOpenClipboard, object: nil)
        },
        6: Binding(keyCode: kVK_ANSI_N) {
            NotificationCenter.default.post(name: .islandOpenNotes, object: nil)
        },
        7: Binding(keyCode: kVK_ANSI_U) {
            NotificationCenter.default.post(name: .islandTogglePinnedNote, object: nil)
        }
    ]

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?
    private var defaultsObserver: NSObjectProtocol?

    /// Four-character code identifying this app's hot keys.
    private static let signature: OSType = 0x49534C44   // "ISLD"

    func start() {

        installHandlerIfNeeded()

        syncRegistration()

        // Follow the Settings toggle live.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.syncRegistration() }
        }
    }

    // MARK: - Registration

    private func syncRegistration() {

        let shouldBeRegistered = AppSettings.globalShortcutsEnabled

        if shouldBeRegistered, hotKeyRefs.isEmpty {

            for (id, binding) in Self.bindings {

                var ref: EventHotKeyRef?

                let status = RegisterEventHotKey(
                    UInt32(binding.keyCode),
                    binding.modifiers,
                    EventHotKeyID(signature: Self.signature, id: id),
                    GetApplicationEventTarget(),
                    0,
                    &ref
                )

                if status == noErr, let ref {
                    hotKeyRefs.append(ref)
                }
            }

        } else if !shouldBeRegistered, !hotKeyRefs.isEmpty {

            hotKeyRefs.forEach { UnregisterEventHotKey($0) }
            hotKeyRefs.removeAll()
        }
    }

    private func installHandlerIfNeeded() {

        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ -> OSStatus in

                var hotKeyID = EventHotKeyID()

                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )

                guard status == noErr else { return status }

                let id = hotKeyID.id

                // Carbon delivers on the main thread.
                MainActor.assumeIsolated {
                    HotKeyManager.bindings[id]?.action()
                }

                return noErr
            },
            1,
            &eventType,
            nil,
            &handlerRef
        )
    }
}
