import SwiftUI
import Combine

/// Owns Priority, Queue, Transitions, and Lifecycle across all activities.
///
/// Per PRODUCT.md's Core Rules: "Only one activity owns the island at a
/// time. The highest priority activity is always displayed." Per the
/// Engineering Constitution: "Activities never compete directly. Activities
/// never interrupt each other." All arbitration happens here, and only here.
@MainActor
final class ActivityManager: ObservableObject {

    /// The activity currently owning the island, or nil if nothing is active.
    /// The WindowManager observes this to decide window visibility/sizing.
    @Published private(set) var ownedActivity: AnyActivity?

    /// A second active activity that has a minimal presentation (music
    /// while a timer owns the notch, a timer while a charger pill does…).
    /// Shown as a small bubble beside the island — never competes for
    /// ownership.
    @Published private(set) var secondaryActivity: AnyActivity?

    /// Set by `IslandRootView`: the cursor is on the secondary activity's
    /// half of a shared pill, so THAT activity is the one expanding.
    /// Deliberately not `@Published` — it's read by `WindowManager` for
    /// hit-testing, and publishing it would only re-render for nothing.
    var expandsSecondary = false

    /// Size of the shared pill (owner left of the notch, secondary
    /// right) when both can share it; `nil` otherwise.
    var splitCompactSize: CGSize? {

        guard
            let ownerEar = ownedActivity?.earWidth,
            let secondaryEar = secondaryActivity?.earWidth
        else {
            return nil
        }

        return CGSize(
            width: DesignTokens.FileDropMetrics.notchWidth
                + max(ownerEar, secondaryEar) * 2,
            height: DesignTokens.TimerMetrics.compactHeight
        )
    }

    /// Width of one half of the shared pill.
    var splitEarWidth: CGFloat? {

        guard
            let ownerEar = ownedActivity?.earWidth,
            let secondaryEar = secondaryActivity?.earWidth
        else {
            return nil
        }

        return max(ownerEar, secondaryEar)
    }

    private var registered: [AnyActivity] = []
    private var cancellables: Set<AnyCancellable> = []

    /// Register an activity module. Order of registration does not matter —
    /// arbitration is always by `ActivityKind` priority, never registration order.
    func register<A: Activity>(_ activity: A) {
        let box = AnyActivity(activity)
        registered.append(box)

        box.isActivePublisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeOwnership()
            }
            .store(in: &cancellables)

        recomputeOwnership()
    }

    /// Re-evaluates which activity should own the island right now.
    /// This is the single place priority arbitration happens — per the
    /// Golden Rule that ownership changes must always be animated, callers
    /// (WindowManager / IslandRootView) are expected to wrap their reaction
    /// to `ownedActivity` changes in `AnimationTokens.ownershipChange`.
    /// Kinds the user explicitly asked for (the launcher, opened by a
    /// click on the notch). They outrank everything while they're up, so
    /// opening the launcher over a playing song or a running timer works,
    /// and the song / timer comes straight back when it closes.
    private var elevatedKinds: Set<ActivityKind> = []

    func setElevated(_ kind: ActivityKind, _ elevated: Bool) {

        // Already in that state: nothing to recompute. (Without this a
        // launcher resigning → asking to be un-elevated → recomputing →
        // resigning… recursed until the stack overflowed.)
        guard elevatedKinds.contains(kind) != elevated else { return }

        if elevated {
            elevatedKinds.insert(kind)
        } else {
            elevatedKinds.remove(kind)
        }

        recomputeOwnership()
    }

    /// Kinds that, for now, rank somewhere other than their usual place —
    /// the calendar's long countdown sits below a running timer, while its
    /// "starting now" alert sits at its usual, higher spot.
    private var rankOverrides: [ActivityKind: Double] = [:]

    func setRankOverride(_ kind: ActivityKind, _ rank: Double?) {

        guard rankOverrides[kind] != rank else { return }

        rankOverrides[kind] = rank

        recomputeOwnership()
    }

    private func rank(_ activity: AnyActivity) -> Double {
        elevatedKinds.contains(activity.kind)
            ? -1
            : rankOverrides[activity.kind] ?? Double(activity.kind.rawValue)
    }

    /// `recomputeOwnership` can be asked to run again from inside itself
    /// (an activity's `didResignActive` may change state that triggers a
    /// recompute). Re-entering would recurse; instead the request is
    /// queued and the loop runs once more after the current pass.
    private var isRecomputing = false
    private var recomputeAgain = false

    private func recomputeOwnership() {

        guard !isRecomputing else {
            recomputeAgain = true
            return
        }

        isRecomputing = true
        defer { isRecomputing = false }

        repeat {
            recomputeAgain = false
            recomputeOwnershipOnce()
        } while recomputeAgain
    }

    private func recomputeOwnershipOnce() {
        let winner = registered
            .filter { $0.isActive }
            .min { rank($0) < rank($1) }

        let secondary = registered
            .filter { $0.isActive && $0.id != winner?.id && $0.minimalView != nil }
            .min { $0.kind < $1.kind }

        if secondary?.id != secondaryActivity?.id {
            secondaryActivity = secondary
        }

        guard winner?.id != ownedActivity?.id else { return }

        // Per Call Philosophy: "After the call ends, the previous activity
        // should return naturally. Nothing should reset unnecessarily."
        // We only notify resign/become-active on the activities actually
        // changing hands — every other activity keeps its state untouched.
        if let previous = ownedActivity, previous.id != winner?.id {
            previous.didResignActive()
        }

        ownedActivity = winner
        winner?.didBecomeActive()
    }
}
