import SwiftUI
import Combine
import AppKit

/// "A file is downloading."
///
/// Lives for as long as a download is in progress (it ranks below Music,
/// so it never pushes playback off the island), then shows a green check
/// for a moment and goes away. Hover to see the file name and sizes.
@MainActor
final class DownloadsActivity: ObservableObject {

    static let kind: ActivityKind = .downloads

    @Published private(set) var isActive: Bool = false
    @Published private(set) var items: [DownloadItem] = []

    /// True for the short "all done" moment after the last download ends.
    @Published private(set) var isComplete: Bool = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private let monitor: DownloadsMonitor
    private var hideWorkItem: DispatchWorkItem?

    /// The most recent downloads, kept so "Show" still works for the
    /// moment after they finish.
    private var lastItems: [DownloadItem] = []

    init(monitor providedMonitor: DownloadsMonitor? = nil) {

        let monitor = providedMonitor ?? DownloadsMonitor()

        self.monitor = monitor

        monitor.onChange = { [weak self] items in
            self?.handle(items)
        }

        monitor.start()
    }

    deinit {
        let monitor = self.monitor
        Task { @MainActor in monitor.stop() }
    }

    // MARK: - Derived

    /// 0...1 across every download when ALL of them report a total;
    /// `nil` (indeterminate) as soon as any one doesn't.
    var fraction: Double? {

        guard !items.isEmpty else { return nil }

        var done: Int64 = 0
        var total: Int64 = 0

        for item in items {

            guard let expected = item.totalBytes else { return nil }

            done += item.bytes
            total += expected
        }

        guard total > 0 else { return nil }

        return min(1, max(0, Double(done) / Double(total)))
    }

    var totalBytes: Int64 {
        items.reduce(0) { $0 + $1.bytes }
    }

    // MARK: - Detection → State

    private func handle(_ newItems: [DownloadItem]) {

        guard AppSettings.showDownloadProgress else {
            items = []
            hide()
            return
        }

        if !newItems.isEmpty {

            hideWorkItem?.cancel()
            hideWorkItem = nil

            isComplete = false
            items = newItems
            lastItems = newItems

            setActive(true)

            return
        }

        // Nothing left. If something WAS downloading, celebrate briefly.
        guard isActive, !isComplete else {
            items = []
            return
        }

        isComplete = true

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AnimationTokens.downloadsCompletionDuration,
            execute: work
        )
    }

    // MARK: - Actions

    /// The browser doing the downloading, if it's running.
    private var browser: NSRunningApplication? {

        for item in (items.isEmpty ? lastItems : items) {
            for id in item.browserBundleIDs {
                if let app = NSRunningApplication
                    .runningApplications(withBundleIdentifier: id).first {
                    return app
                }
            }
        }

        return nil
    }

    var canOpenBrowser: Bool { browser != nil }

    /// Brings the downloading browser to the front.
    func openBrowser() {
        browser?.activate()
    }

    /// Shows the file in Finder — the in-progress file while it's
    /// downloading, the finished file afterwards.
    func showInFinder() {

        guard let item = (items.isEmpty ? lastItems : items).first else { return }

        let finished = item.url
            .deletingLastPathComponent()
            .appendingPathComponent(item.name)

        let target = FileManager.default.fileExists(atPath: finished.path)
            ? finished
            : item.url

        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    // MARK: - Visibility

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        isComplete = false

        setActive(false)
    }

    private func setActive(_ shouldBeActive: Bool) {

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    /// Something outranked the download. The download itself carries on,
    /// and `isActive` stays true while it does, so this returns on its own.
    func didResignActive() {}

    // MARK: - Sizing

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.DownloadsMetrics.expandedWidth,
            height: DesignTokens.DownloadsMetrics.expandedHeight
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        DownloadsIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension DownloadsActivity: Activity {}
