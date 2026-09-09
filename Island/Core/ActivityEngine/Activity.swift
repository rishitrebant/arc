import SwiftUI
import Combine

/// The contract every Activity module must fulfill.
///
/// Per Engineering Constitution — "Every activity owns Detection, State,
/// Rendering, Actions" and "Activities never directly communicate. Activities
/// publish state changes." An Activity never talks to ActivityManager's
/// internals and never talks to another Activity; it only publishes whether
/// it currently wants to be visible.
@MainActor
protocol Activity: AnyObject, ObservableObject {
    /// Which slot in the priority system this activity occupies.
    static var kind: ActivityKind { get }

    /// Whether this activity currently has something worth showing.
    /// The ActivityManager observes this to decide ownership — it never
    /// inspects an activity's internal state directly.
    var isActive: Bool { get }

    /// Erased publisher so ActivityManager can observe `isActive` without
    /// knowing the concrete activity type.
    var isActivePublisher: AnyPublisher<Bool, Never> { get }

    /// Single island presentation, parameterized by expansion state — NOT
    /// two separate view types being swapped. This is deliberate: see
    /// `MusicIslandView`'s doc comment for why having two independently
    /// type-erased views (the old `compactView()`/`expandedView()`) made
    /// smooth animation architecturally impossible, not just hard to tune.
    associatedtype IslandContent: View
    @ViewBuilder func islandView(isExpanded: Bool) -> IslandContent

    /// Called by ActivityManager when this activity begins owning the island.
    func didBecomeActive()

    /// Called when a higher-priority activity takes ownership away.
    /// The activity should preserve its state so it can "return exactly
    /// where it left off" (Call Philosophy) rather than resetting.
    func didResignActive()

    /// How large the visible pill is, compact and expanded. Also what
    /// `WindowManager` uses to size its AppKit-level click-through hit
    /// region while this activity owns the island — the two are always
    /// kept in sync since they both come from here.
    ///
    /// Instance properties, not static: an activity's own expanded size
    /// can legitimately differ by its internal state (see
    /// `FileDropActivity`, whose expanded size is the small drag-choice
    /// panel while a drag is hovering, and a different size for the
    /// persistent shelf grid otherwise) — a single fixed constant per
    /// activity type isn't always enough.
    ///
    /// Defaulted below to Music's own measured sizes purely so every
    /// activity that doesn't need to override this keeps compiling
    /// unchanged.
    var compactSize: CGSize { get }
    var expandedSize: CGSize { get }
}

extension Activity {

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.compactWidth,
            height: DesignTokens.MusicMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.expandedWidth,
            height: DesignTokens.MusicMetrics.expandedHeight
        )
    }
}
