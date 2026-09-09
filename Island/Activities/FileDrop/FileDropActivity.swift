import SwiftUI
import Combine

/// Drives the shelf + "bring a file to the notch" activity.
///
/// Redesigned from the original two-tile (shelf vs AirDrop) split:
/// dropping a file anywhere on the panel now always goes to the shelf.
/// AirDrop is a separate action — a button inside the shelf view that
/// hands whatever's currently in the shelf to the real system picker.
///
/// Drag detection is two-stage, per direct request:
///   - `isDragNear` — true the instant a compatible drag enters the
///     generous catch zone. Drives a glow ONLY; does not take
///     ownership of the island (Music, if playing, keeps showing).
///   - `isDragHovering` — true `FileDropConfiguration.dragRevealDelay`
///     seconds after that, IF the drag is still near. This is what
///     actually takes ownership and shows the full panel.
///
/// `isActive` — and therefore ownership — is driven by `isDragHovering`
/// and `shelfItems`, deliberately NOT `isDragNear`: the glow phase is
/// meant to layer on top of whatever's already showing, not preempt it.
@MainActor
final class FileDropActivity: ObservableObject {

    static let kind: ActivityKind = .fileDrop

    @Published private(set) var isActive: Bool = false

    @Published private(set) var shelfItems: [ShelfItem] = []

    /// Instant, cosmetic-only — see the type doc above.
    @Published private(set) var isDragNear = false

    /// Delayed, ownership-taking — see the type doc above.
    @Published private(set) var isDragHovering = false

    /// Item count shown on the panel while hovering, before the drop —
    /// comes from the drag session's item providers, not
    /// `shelfItems.count`.
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
    private var dragRevealWorkItem: DispatchWorkItem?
    private var dragExitDebounceWorkItem: DispatchWorkItem?

    // MARK: - Drag Lifecycle

    /// Called the instant a compatible drag enters the catch zone.
    /// Safe to call repeatedly (e.g. as the item count changes) —
    /// updates `draggedItemCount` each time, but only arms the
    /// reveal-delay timer once per drag session (`isDragNear` guards
    /// that).
    func dragEntered(itemCount: Int) {

        // Cancels a pending debounced exit (see `dragExited` below) —
        // the drag came back before it fired, so nothing should reset.
        dragExitDebounceWorkItem?.cancel()
        dragExitDebounceWorkItem = nil

        draggedItemCount = itemCount

        guard !isDragNear else { return }

        isDragNear = true

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isDragNear else { return }
            self.isDragHovering = true
            self.publishActive()
        }

        dragRevealWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + FileDropConfiguration.dragRevealDelay,
            execute: work
        )
    }

    /// Called when the drag leaves the catch zone without being dropped.
    ///
    /// Debounced, deliberately — even with a generous catch zone, a
    /// brief, imprecise wobble in cursor position (very common on a
    /// trackpad-driven drag) would otherwise immediately cancel the
    /// half-second reveal timer and reset `isDragNear`, restarting the
    /// whole sequence from zero. That's what was actually behind the
    /// reported flickering: the exit was real, correct, and immediate
    /// every single time the cursor so much as twitched near the
    /// boundary. Waiting a short grace period before actually resetting
    /// anything — canceled if the drag re-enters first — fixes that
    /// without needing pixel-perfect steadiness from the user.
    func dragExited() {

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dragRevealWorkItem?.cancel()
            self.dragRevealWorkItem = nil
            self.isDragNear = false
            self.isDragHovering = false
            self.publishActive()
        }

        dragExitDebounceWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + FileDropConfiguration.dragExitGracePeriod,
            execute: work
        )
    }

    // MARK: - Drop Handling

    /// The only drop destination now — see the type doc above for why
    /// the old shelf/AirDrop tile split went away.
    func dropOnShelf(files: [DroppedFile]) {

        dragRevealWorkItem?.cancel()
        dragRevealWorkItem = nil
        dragExitDebounceWorkItem?.cancel()
        dragExitDebounceWorkItem = nil

        guard !files.isEmpty else {
            isDragNear = false
            isDragHovering = false
            publishActive()
            return
        }

        let now = Date()
        let expiresAt = now.addingTimeInterval(FileDropConfiguration.shelfDuration)

        let newItems = files.map {
            ShelfItem(
                url: $0.url,
                displayName: $0.displayName,
                addedAt: now,
                expiresAt: expiresAt
            )
        }

        shelfItems.append(contentsOf: newItems)

        for item in newItems {
            scheduleExpiry(for: item)
        }

        isDragNear = false
        isDragHovering = false
        triggerFreshReveal()
        publishActive()
    }

    /// Triggered by the AirDrop button inside the shelf view — hands
    /// everything CURRENTLY in the shelf to the real system picker.
    /// There's nothing for this activity to keep showing afterward (see
    /// the AirDrop-receiving conversation: we can mirror at most, never
    /// own, that flow), so this is fire-and-forget from here on.
    func airDropShelfItems() {

        guard !shelfItems.isEmpty else { return }

        presentAirDropPicker?(shelfItems.map(\.url))
    }

    func removeShelfItem(_ id: UUID) {

        guard let item = shelfItems.first(where: { $0.id == id }) else {
            return
        }

        shelfItems.removeAll { $0.id == id }

        expiryTimers[id]?.invalidate()
        expiryTimers[id] = nil

        ShelfFileStore.remove(item.url)

        publishActive()
    }

    /// The red trash button — "discard the shelf." Clears everything at
    /// once, distinct from `removeShelfItem`'s one-at-a-time delete.
    func clearShelf() {

        for item in shelfItems {
            expiryTimers[item.id]?.invalidate()
            ShelfFileStore.remove(item.url)
        }

        expiryTimers.removeAll()
        shelfItems.removeAll()

        publishActive()
    }

    /// Called by `AppDelegate` when the user clicks anywhere outside
    /// the expanded island — see `WindowManager.onOutsideClickWhileFileDropExpanded`.
    /// Cancels an in-progress reveal early rather than waiting out its
    /// remaining duration. A held-button drag can't really be
    /// interrupted by a "click" (there's no button-up), so this is
    /// mainly about `isShowingFreshReveal`; the drag flags are reset
    /// too regardless, defensively.
    func dismissExpandedState() {

        dragRevealWorkItem?.cancel()
        dragRevealWorkItem = nil
        dragExitDebounceWorkItem?.cancel()
        dragExitDebounceWorkItem = nil

        isDragNear = false
        isDragHovering = false

        revealCollapseWorkItem?.cancel()
        revealCollapseWorkItem = nil
        isShowingFreshReveal = false

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

        dragRevealWorkItem?.cancel()
        dragRevealWorkItem = nil
        dragExitDebounceWorkItem?.cancel()
        dragExitDebounceWorkItem = nil
        isDragNear = false
        isDragHovering = false
    }

    // MARK: - Sizing

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.FileDropMetrics.compactWidth,
            height: DesignTokens.FileDropMetrics.compactHeight
        )
    }

    /// Two sizes now, not one — per direct request: the Shelf/AirDrop
    /// button row shouldn't be visible at all until something's
    /// actually been dropped, at which point the island grows smoothly
    /// into the taller size to reveal it.
    var expandedSize: CGSize {
        shelfItems.isEmpty
            ? CGSize(
                width: DesignTokens.FileDropMetrics.expandedEmptyWidth,
                height: DesignTokens.FileDropMetrics.expandedEmptyHeight
            )
            : CGSize(
                width: DesignTokens.FileDropMetrics.expandedWithItemsWidth,
                height: DesignTokens.FileDropMetrics.expandedWithItemsHeight
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
