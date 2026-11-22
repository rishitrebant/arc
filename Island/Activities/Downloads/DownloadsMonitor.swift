import Foundation

/// One file currently being downloaded.
struct DownloadItem: Equatable, Identifiable {

    let id: String          // path of the in-progress file
    let name: String        // final file name, without the browser's suffix
    let bytes: Int64
    /// Known only where the browser records it (Safari). `nil` otherwise.
    let totalBytes: Int64?

    /// Which browser writes this kind of temporary file — the suffix is
    /// the only clue. Chrome-family browsers all share `.crdownload`, so
    /// that one lists every candidate and the running one is picked.
    let browserBundleIDs: [String]

    var url: URL { URL(fileURLWithPath: id) }
}

/// Watches ~/Downloads for browser downloads in progress.
///
/// Browsers write to a temporary name until the download finishes:
///   - Safari:  `Name.ext.download` — a bundle whose Info.plist records
///     bytes so far AND the total, so progress is exact.
///   - Chrome / Edge / Brave / Arc: `Name.ext.crdownload`
///   - Firefox: `Name.ext.part`
///   - Opera:   `Name.ext.opdownload`
/// For the non-Safari browsers only the bytes so far are knowable, so
/// the island shows indeterminate progress for those.
///
/// Polled once a second: a folder watcher would still need to poll file
/// sizes to follow progress, and this keeps one code path.
@MainActor
final class DownloadsMonitor {

    var onChange: (([DownloadItem]) -> Void)?

    private static let suffixes = [".download", ".crdownload", ".part", ".opdownload"]

    private var timer: Timer?
    private var last: [DownloadItem] = []

    func start() {

        guard timer == nil else { return }

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {

        let now = Self.scan()

        guard now != last else { return }

        last = now
        onChange?(now)
    }

    // MARK: - Scanning

    private static func scan() -> [DownloadItem] {

        guard
            let folder = FileManager.default.urls(
                for: .downloadsDirectory, in: .userDomainMask
            ).first,
            let urls = try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return urls.compactMap(item(for:)).sorted { $0.name < $1.name }
    }

    private static func item(for url: URL) -> DownloadItem? {

        let fileName = url.lastPathComponent

        guard let suffix = suffixes.first(where: { fileName.hasSuffix($0) }) else {
            return nil
        }

        let name = String(fileName.dropLast(suffix.count))

        if suffix == ".download" {
            return safariItem(url: url, name: name)
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return DownloadItem(
            id: url.path,
            name: name,
            bytes: Int64(size),
            totalBytes: nil,
            browserBundleIDs: browsers(forSuffix: suffix)
        )
    }

    /// Safari's `.download` bundle: Info.plist holds the progress.
    private static func safariItem(url: URL, name: String) -> DownloadItem {

        let plistURL = url.appendingPathComponent("Info.plist")

        var bytes: Int64 = 0
        var total: Int64?

        if
            let data = try? Data(contentsOf: plistURL),
            let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil
            ) as? [String: Any]
        {
            bytes = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value ?? 0

            if let expected = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value,
               expected > 0 {
                total = expected
            }
        }

        return DownloadItem(
            id: url.path,
            name: name,
            bytes: bytes,
            totalBytes: total,
            browserBundleIDs: browsers(forSuffix: ".download")
        )
    }

    private static func browsers(forSuffix suffix: String) -> [String] {

        switch suffix {
        case ".download":
            return ["com.apple.Safari"]
        case ".crdownload":
            return [
                "com.google.Chrome", "com.microsoft.edgemac",
                "com.brave.Browser", "company.thebrowser.Browser",
                "com.vivaldi.Vivaldi"
            ]
        case ".part":
            return ["org.mozilla.firefox"]
        case ".opdownload":
            return ["com.operasoftware.Opera"]
        default:
            return []
        }
    }
}
