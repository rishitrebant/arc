import Foundation
import AppKit

/// Turns macOS Low Power Mode on.
///
/// macOS has no public API for this — `ProcessInfo.isLowPowerModeEnabled`
/// is read-only. The only supported way to change it from an app is
/// `pmset`, which needs administrator rights, so this asks macOS to show
/// its standard "enter your password" dialog (via `osascript`) and runs
/// `pmset -a lowpowermode 1` once authorized.
///
/// `Process` is used instead of `NSAppleScript` on purpose: the password
/// dialog blocks until the user answers, and `Process` lets that happen
/// without freezing the island.
enum LowPowerModeController {

    enum Result {
        case enabled
        /// User dismissed the password dialog.
        case cancelled
        case failed
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    static func enable(
        completion: @escaping @MainActor @Sendable (Result) -> Void
    ) {

        let script = """
        do shell script "/usr/bin/pmset -a lowpowermode 1" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = Pipe()

        process.terminationHandler = { finished in

            let errorText = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                as: UTF8.self
            )

            let result: Result

            if finished.terminationStatus == 0 {
                result = .enabled
            } else if errorText.contains("-128") {
                // AppleScript's "User canceled." error number.
                result = .cancelled
            } else {
                result = .failed
            }

            Task { @MainActor in
                completion(result)
            }
        }

        do {
            try process.run()
        } catch {
            Task { @MainActor in
                completion(.failed)
            }
        }
    }

    /// Fallback when the automatic route fails: open System Settings'
    /// Battery pane so the user can flip the switch themselves.
    static func openBatterySettings() {

        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.Battery-Settings.extension"
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}
