import AppKit
import Sparkle

/// Wraps Sparkle's standard updater. The feed URL and public signing key
/// live in `Config/Info-Extra.plist` (`SUFeedURL`, `SUPublicEDKey`).
///
/// Updates are downloaded in the background as soon as they're found, so
/// the About tab can offer one button — "Update and Restart" — that
/// installs it and relaunches ARC straight away.
///
/// Touch `UpdateController.shared` once at launch so Sparkle starts its
/// scheduled background checks.
@MainActor
final class UpdateController: NSObject, ObservableObject, SPUUpdaterDelegate {

    static let shared = UpdateController()

    /// The version Sparkle found, while there's one newer than this.
    @Published private(set) var availableVersion: String?

    /// It's downloaded and can be installed — and ARC relaunched — now.
    @Published private(set) var isReadyToInstall = false

    private var installNow: (() -> Void)?

    private var controller: SPUStandardUpdaterController!

    var updater: SPUUpdater {
        controller.updater
    }

    override init() {

        super.init()

        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )

        // Fetch updates quietly, so "Update and Restart" is instant.
        controller.updater.automaticallyDownloadsUpdates = true
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

    /// Installs the update and relaunches ARC. If it hasn't finished
    /// downloading yet, this runs Sparkle's own flow instead.
    func updateAndRestart() {

        if let installNow {
            installNow()
        } else {
            controller.checkForUpdates(nil)
        }
    }

    // MARK: - SPUUpdaterDelegate

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {

        let version = item.displayVersionString

        Task { @MainActor in self.availableVersion = version }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {

        Task { @MainActor in
            self.availableVersion = nil
            self.isReadyToInstall = false
            self.installNow = nil
        }
    }

    /// The update is downloaded and staged. Sparkle would install it when
    /// ARC quits; keep the handle so the About button can do it right now.
    nonisolated func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {

        Task { @MainActor in
            self.availableVersion = item.displayVersionString
            self.installNow = immediateInstallHandler
            self.isReadyToInstall = true
        }

        return true
    }
}
