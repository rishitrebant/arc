import SwiftUI
import Combine

/// Drives the shelf + "bring a file to the notch" activity.
///
/// Two conceptually separate states live here, both under one activity
/// since they share the same island real estate and priority slot:
///   - `isDragHovering` — a file is currently being dragged near the
///     generous drag-catch zone (see `WindowManager`), not yet dropped.
///     Shows the two-tile shelf/AirDrop choice panel.
///   - `shelfItems` — files already dropped into the shelf, persisted
///     for `FileDropConfiguration.shelfDuration` each.
///
/// `isActive` is true if either is non-empty, which is all
/// `ActivityManager`'s existing priority arbitration needs to correctly
/// take the island away from Music while either is going on, and hand
/// it back automatically once both are empty — see `ActivityKind`.
@MainActor
final class FileDropActivity: ObservableObject {

    static let kind: ActivityKind = .fileDrop

    @Published private(set) var isActive: Bool = false

    @Published private(set) var shelfItems: [ShelfItem] = []

    @Published private(set) var isDragHovering = false

    /// Item count shown on the drag-choice panel while hovering, before
    /// the user has committed to a tile — comes from the drag session's
    /// item providers, not `shelfItems.count`.
    @Published private(set) var draggedItemCount = 0

    /// True for `FileDropConfiguration.postDropRevealDuration` right
    /// after a drop — `FileDropIslandView` uses this to force the
    /// expanded layout briefly before collapsing back to the compact
    /// chip row on its own.
    @Published private(set) var isShowingFreshReveal = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — actually presenting the system AirDrop
    /// sheet needs an `NSView`/`NSWindow` to anchor to, which this
    /// activity has no business owning itself.
    var presentAirDropPicker: (([URL]) -> Void)?

    private var expiryTimers: [UUID: Timer] = [:]
    private var revealCollapseWorkItem: DispatchWorkItem?

    // MARK: - Drag Lifecycle

    /// Called while a compatible drag is hovering the catch zone, not
    /// yet dropped. Safe to call repeatedly (e.g. as the item count
    /// changes) — updates `draggedItemCount` each time.
    func dragEntered(itemCount: Int) {

        draggedItemCount = itemCount
        isDragHovering = true
        publishActive()
    }

    /// Called when the drag leaves the catch zone without being dropped
    /// on either tile.
    func dragExited() {

        isDragHovering = false
        publishActive()
    }

    // MARK: - Drop Handling

    func dropOnShelf(urls: [URL]) {

        guard !urls.isEmpty else {
            isDragHovering = false
            publishActive()
            return
        }

        let now = Date()
        let expiresAt = now.addingTimeInterval(FileDropConfiguration.shelfDuration)

        let newItems = urls.map {
            ShelfItem(url: $0, addedAt: now, expiresAt: expiresAt)
        }

        shelfItems.append(contentsOf: newItems)

        for item in newItems {
            scheduleExpiry(for: item)
        }

        isDragHovering = false
        triggerFreshReveal()
        publishActive()
    }

    /// Doesn't touch the shelf — hands the files straight to the real
    /// system AirDrop sheet. There's nothing for this activity to keep
    /// showing afterward (see the AirDrop-receiving conversation: we
    /// can mirror at most, never own, that flow), so this just ends the
    /// drag-hover state once the picker is asked to appear.
    func dropOnAirDrop(urls: [URL]) {

        guard !urls.isEmpty else {
            isDragHovering = false
            publishActive()
            return
        }

        isDragHovering = false
        publishActive()

        presentAirDropPicker?(urls)
    }

    func removeShelfItem(_ id: UUID) {

        shelfItems.removeAll { $0.id == id }

        expiryTimers[id]?.invalidate()
        expiryTimers[id] = nil

        publishActive()
    }

    // MARK: - Expiry

    private func scheduleExpiry(for item: ShelfItem) {

        let timer = Timer.scheduledTimer(
            withTimeInterval: FileDropConfiguration.shelfDuration,
            repeats: false
        ) { [weak self] _ in

            Task { @MainActor [weak self] in
                self?.removeShelfItem(item.id)
            }
        }

        expiryTimers[item.id] = timer
    }

    private func triggerFreshReveal() {

        isShowingFreshReveal = true

        revealCollapseWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.isShowingFreshReveal = false
        }

        revealCollapseWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + FileDropConfiguration.postDropRevealDuration,
            execute: work
        )
    }

    private func publishActive() {

        let shouldBeActive = isDragHovering || !shelfItems.isEmpty

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    /// Shouldn't really happen — `fileDrop` sits above every other
    /// content activity except calls — but handled cleanly regardless:
    /// a hovering (not-yet-dropped) drag gets cancelled rather than
    /// left in a stuck state. Items already in the shelf are untouched
    /// and keep expiring on their own schedule in the background.
    func didResignActive() {

        if isDragHovering {
            isDragHovering = false
        }
    }

    // MARK: - Sizing

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.FileDropMetrics.compactWidth,
            height: DesignTokens.FileDropMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        isDragHovering
            ? CGSize(
                width: DesignTokens.FileDropMetrics.dragPanelWidth,
                height: DesignTokens.FileDropMetrics.dragPanelHeight
            )
            : CGSize(
                width: DesignTokens.FileDropMetrics.expandedWidth,
                height: DesignTokens.FileDropMetrics.expandedHeight
            )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        FileDropIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension FileDropActivity: Activity {}
