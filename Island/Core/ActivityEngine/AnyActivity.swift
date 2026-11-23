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
    private let _islandView: (Bool) -> AnyView
    private let _didBecomeActive: () -> Void
    private let _didResignActive: () -> Void
    private let _compactSize: () -> CGSize
    private let _expandedSize: () -> CGSize
    private let _compactCenterShift: () -> CGFloat
    private let _shadowAccent: () -> Color?
    private let _minimalView: (() -> AnyView)?
    private let _earWidth: (() -> CGFloat)?
    private let _earView: ((EarSide) -> AnyView)?

    init<A: Activity>(_ activity: A) {
        self.kind = A.kind
        self._isActive = { activity.isActive }
        self._isActivePublisher = { activity.isActivePublisher }
        self._islandView = { isExpanded in AnyView(activity.islandView(isExpanded: isExpanded)) }
        self._didBecomeActive = { activity.didBecomeActive() }
        self._didResignActive = { activity.didResignActive() }
        self._compactSize = { activity.compactSize }
        self._expandedSize = { activity.expandedSize }
        self._compactCenterShift = { activity.compactCenterShift }
        self._shadowAccent = { activity.shadowAccent }

        if let presentable = activity as? MinimalPresentable {
            self._minimalView = { presentable.minimalView() }
            self._earWidth = { presentable.earWidth }
            self._earView = { presentable.earView(side: $0) }
        } else {
            self._minimalView = nil
            self._earWidth = nil
            self._earView = nil
        }
    }

    var isActive: Bool { _isActive() }
    var isActivePublisher: AnyPublisher<Bool, Never> { _isActivePublisher() }
    /// One call site, one erased view — `IslandRootView` no longer chooses
    /// between two different `AnyView`s. Same underlying concrete type
    /// (e.g. `MusicIslandView`) erased every time, just with a different
    /// `isExpanded` value, which is what lets SwiftUI treat this as a
    /// single view updating rather than one being swapped for another.
    func islandView(isExpanded: Bool) -> AnyView { _islandView(isExpanded) }
    func didBecomeActive() { _didBecomeActive() }
    func didResignActive() { _didResignActive() }
    /// The small detached bubble this activity shows while another one
    /// owns the notch, or `nil` if it has no such presentation.
    var minimalView: AnyView? { _minimalView?() }

    /// Width of this activity's half of a shared pill, or `nil` if it
    /// can't share the notch that way.
    var earWidth: CGFloat? { _earWidth?() }

    func earView(side: EarSide) -> AnyView? { _earView?(side) }
    var compactCenterShift: CGFloat { _compactCenterShift() }
    var shadowAccent: Color? { _shadowAccent() }
    var compactSize: CGSize { _compactSize() }
    var expandedSize: CGSize { _expandedSize() }
}
