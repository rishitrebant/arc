import SwiftUI
import Combine

/// Type-erased box around a concrete `Activity`.
///
/// `Activity` has associated types (its compact/expanded view types), so it
/// can't be stored directly in a heterogeneous collection. ActivityManager
/// needs to hold Music, Bluetooth, Calls, etc. side by side — this box makes
/// that possible without any activity knowing the others exist.
@MainActor
final class AnyActivity: Identifiable {
    let id = UUID()
    let kind: ActivityKind

    private let _isActive: () -> Bool
    private let _isActivePublisher: () -> AnyPublisher<Bool, Never>
    private let _compactView: () -> AnyView
    private let _expandedView: () -> AnyView
    private let _didBecomeActive: () -> Void
    private let _didResignActive: () -> Void

    init<A: Activity>(_ activity: A) {
        self.kind = A.kind
        self._isActive = { activity.isActive }
        self._isActivePublisher = { activity.isActivePublisher }
        self._compactView = { AnyView(activity.compactView()) }
        self._expandedView = { AnyView(activity.expandedView()) }
        self._didBecomeActive = { activity.didBecomeActive() }
        self._didResignActive = { activity.didResignActive() }
    }

    var isActive: Bool { _isActive() }
    var isActivePublisher: AnyPublisher<Bool, Never> { _isActivePublisher() }
    func compactView() -> AnyView { _compactView() }
    func expandedView() -> AnyView { _expandedView() }
    func didBecomeActive() { _didBecomeActive() }
    func didResignActive() { _didResignActive() }
}
