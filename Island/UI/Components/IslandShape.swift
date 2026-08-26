import SwiftUI

/// The island's pill/card shape — square top corners, rounded bottom
/// corners in compact; rounded on all corners in expanded.
///
/// This is a real `Shape` with explicit `animatableData`, not just a
/// factory returning `UnevenRoundedRectangle` directly. That distinction
/// matters for the morph: `matchedGeometryEffect` (used on this shape's
/// view in both `MusicCompactView` and `MusicExpandedView`) interpolates
/// the view's FRAME — its position and size — but it does nothing for the
/// shape's own internal parameters. Whether the corner radii themselves
/// smoothly animate from `(0, 12)` to `(18, 18)`, instead of snapping
/// instantly to the new value, depends entirely on this type correctly
/// exposing those radii as `animatableData`. Relying on
/// `UnevenRoundedRectangle` to already do that for us was a real risk, not
/// a formality — so it's made explicit here instead.
struct IslandShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        ).path(in: rect)
    }
}
