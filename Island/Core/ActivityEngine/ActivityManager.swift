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
    private func recomputeOwnership() {
        let winner = registered
            .filter { $0.isActive }
            .min { $0.kind < $1.kind }

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
