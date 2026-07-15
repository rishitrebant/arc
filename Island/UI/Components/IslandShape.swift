import SwiftUI

/// Factory for the island's body shape: square top corners (flush against
/// the physical notch) and rounded bottom corners only, using Apple's
/// continuous ("squircle") corner curve rather than a circular-arc rounded
/// rect — this is what actually reads as a native Apple component instead
/// of a generic rounded rectangle.
///
/// `UnevenRoundedRectangle` is a native SwiftUI `Shape` (macOS 13+), so its
/// corner radii interpolate automatically when `bottomRadius` changes under
/// animation — no hand-rolled `animatableData` needed.
enum IslandShape {
    static func body(bottomRadius: CGFloat) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: 0,
            style: .continuous
        )
    }
}
