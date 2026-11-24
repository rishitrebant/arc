import AppKit
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL and public signing key
/// live in `Config/Info-Extra.plist` (`SUFeedURL`, `SUPublicEDKey`).
///
/// Touch `UpdateController.shared` once at launch so Sparkle starts its
/// scheduled background checks.
@MainActor
final class UpdateController: NSObject {

    static let shared = UpdateController()

    private let controller =
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

    var updater: SPUUpdater {
        controller.updater
    }

    /// Whether Sparkle checks for updates on its own (roughly daily).
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }

    /// Shows Sparkle's "Check for Updates" flow, including the "you're up
    /// to date" alert.
    @objc
    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
