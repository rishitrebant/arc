import AppKit
import Carbon.HIToolbox

/// Opens the launcher's clipboard when ⌘V is pressed, in any app.
///
/// Watching keys system-wide needs the Input Monitoring permission, so
/// this only runs while "Open the clipboard when I paste" is on, and asks
/// for the permission the moment it's switched on. It only ever looks for
/// ⌘V — nothing else is read or stored.
///
/// A monitor made before the permission is granted never hears anything,
/// so while it's wanted this checks every couple of seconds and installs
/// the monitor as soon as access appears — no relaunch needed.
@MainActor
final class PasteMonitor {

    private var monitor: Any?
    private var observer: Task<Void, Never>?
    private var accessTimer: Timer?

    func start() {

        sync()

        // Follow the Settings toggle live.
        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            ) {
                self?.sync()
            }
        }
    }

    /// Whether macOS currently lets ARC watch for key presses.
    static var hasAccess: Bool {
        CGPreflightListenEventAccess()
    }

    private func sync() {

        guard AppSettings.openClipboardOnPaste else {
            uninstall()
            return
        }

        if !Self.hasAccess, accessTimer == nil {

            CGRequestListenEventAccess()

            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.sync() }
            }

            RunLoop.main.add(timer, forMode: .common)
            accessTimer = timer
        }

        if Self.hasAccess {

            accessTimer?.invalidate()
            accessTimer = nil

            if monitor == nil { install() }
        }
    }

    private func install() {

        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in

            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Plain ⌘V only — not ⌘⇧V, ⌘⌥V and so on.
            guard
                event.keyCode == UInt16(kVK_ANSI_V),
                modifiers.contains(.command),
                modifiers.isDisjoint(with: [.shift, .option, .control])
            else {
                return
            }

            NotificationCenter.default.post(name: .islandOpenClipboard, object: nil)
        }
    }

    private func uninstall() {

        accessTimer?.invalidate()
        accessTimer = nil

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
