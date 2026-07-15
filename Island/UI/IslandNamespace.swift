import SwiftUI

/// Carries the single `@Namespace` that `IslandRootView` owns down to
/// whichever activity's compact/expanded views are on screen, so shared
/// elements (the island body, artwork, waveform) can use
/// `matchedGeometryEffect` to morph continuously between them.
///
/// This goes through the environment rather than a parameter on the
/// `Activity` protocol so no protocol signatures had to change for a
/// polish-only pass.
private struct IslandNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    var islandNamespace: Namespace.ID? {
        get { self[IslandNamespaceKey.self] }
        set { self[IslandNamespaceKey.self] = newValue }
    }
}

extension View {
    /// Applies `matchedGeometryEffect` using the shared island namespace,
    /// if one is present in the environment. No-ops safely otherwise
    /// (e.g. in previews) instead of force-unwrapping.
    @ViewBuilder
    func islandMatchedGeometry(id: String, namespace: Namespace.ID?) -> some View {
        if let namespace {
            self.matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
