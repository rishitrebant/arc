import SwiftUI

/// The island's pill/card shape — square top corners, rounded bottom
/// corners in compact; rounded on all corners in expanded.
///
/// This is a real `Shape` with explicit `animatableData`, not just a
/// factory returning `UnevenRoundedRectangle` directly. That distinction
/// matters for the morph: `matchedGeometryEffect` (used on this shape's
/// view in both compact and expanded states within `MusicIslandView`)
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

    /// How far the top edge flares out past each side wall, in points.
    ///
    /// The real notch doesn't meet the top of the screen at a right
    /// angle: its side walls sweep outward in a small concave curve and
    /// merge into the edge. A flat-topped pill next to it reads as a
    /// separate object; with this flare it reads as part of the notch.
    ///
    /// Only flat-topped shapes get it (`topRadius` near 0). As the top
    /// radius grows toward a fully rounded card the flare fades out, so
    /// the two states morph into each other continuously.
    private var flare: CGFloat {
        DesignTokens.Shape.notchFlare * max(0, 1 - topRadius / 12)
    }

    func path(in rect: CGRect) -> Path {

        let f = flare

        guard f > 0.5 else {
            return UnevenRoundedRectangle(
                topLeadingRadius: topRadius,
                bottomLeadingRadius: bottomRadius,
                bottomTrailingRadius: bottomRadius,
                topTrailingRadius: topRadius,
                style: .continuous
            ).path(in: rect)
        }

        let br = max(0, min(bottomRadius, rect.height / 2 - f / 2, rect.width / 2))

        // Quarter-circle Bézier constant.
        let k: CGFloat = 0.5523 * f

        var path = Path()

        // Left flare: from the ceiling, curving down into the left wall.
        path.move(to: CGPoint(x: rect.minX - f, y: rect.minY))

        path.addCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + f),
            control1: CGPoint(x: rect.minX - f + k, y: rect.minY),
            control2: CGPoint(x: rect.minX, y: rect.minY + f - k)
        )

        // Left wall, bottom-left corner, bottom edge, bottom-right corner.
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - br))

        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.minX + br, y: rect.maxY),
            radius: br
        )

        path.addLine(to: CGPoint(x: rect.maxX - br, y: rect.maxY))

        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.maxY - br),
            radius: br
        )

        // Right wall, curving out into the ceiling.
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))

        path.addCurve(
            to: CGPoint(x: rect.maxX + f, y: rect.minY),
            control1: CGPoint(x: rect.maxX, y: rect.minY + f - k),
            control2: CGPoint(x: rect.maxX + f - k, y: rect.minY)
        )

        path.closeSubpath()

        return path
    }
}


/// The island's surface for activities that have a compact pill AND an
/// expanded card.
///
/// The black shape springs between the two sizes. The CONTENT never
/// reflows while that happens: each state's content is laid out once, at
/// its own final size, pinned to the top-centre, and revealed through a
/// mask that is the live (growing / shrinking) shape. So nothing slides
/// or squeezes — the island simply opens out from the notch and the
/// content fades in once there is room, like the Dynamic Island.
struct IslandMorphSurface<Compact: View, Expanded: View>: View {

    let isExpanded: Bool
    let compactSize: CGSize
    let expandedSize: CGSize
    @ViewBuilder let compact: Compact
    @ViewBuilder let expanded: Expanded

    private var canvas: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visible: CGSize {
        isExpanded ? expandedSize : compactSize
    }

    private var shape: IslandShape {
        IslandShape(
            topRadius: isExpanded
                ? DesignTokens.Shape.expandedTopRadius
                : DesignTokens.Shape.compactTopRadius,
            bottomRadius: isExpanded
                ? DesignTokens.Shape.expandedBottomRadius
                : DesignTokens.Shape.compactBottomRadius
        )
    }

    var body: some View {

        ZStack(alignment: .top) {

            shape
                .fill(DesignTokens.Color.islandBackground)
                .frame(width: visible.width, height: visible.height)

            ZStack(alignment: .top) {

                if isExpanded {

                    expanded
                        .frame(width: expandedSize.width, height: expandedSize.height)
                        .transition(
                            // Fades in once there's room; on the way out it
                            // clears at once, before the shape shrinks.
                            .asymmetric(
                                insertion: .opacity.animation(
                                    AnimationTokens.shapeSpring
                                        .delay(AnimationTokens.contentRevealDelay)
                                ),
                                removal: .opacity.animation(.easeIn(duration: 0.07))
                            )
                        )

                } else {

                    compact
                        .frame(width: compactSize.width, height: compactSize.height)
                        .transition(
                            .opacity.animation(.easeOut(duration: 0.14))
                        )
                }
            }
            .frame(width: canvas.width, height: canvas.height, alignment: .top)
            .mask(alignment: .top) {
                shape
                    .fill(Color.black)
                    .frame(width: visible.width, height: visible.height)
            }
        }
        .frame(width: canvas.width, height: canvas.height, alignment: .top)
        .animation(
            AnimationTokens.shapeMorph(isExpanding: isExpanded),
            value: isExpanded
        )
    }
}


/// One of the two small concave "fillets" where a flat-topped pill
/// meets the top of the screen — the same flare `IslandShape` draws, as a
/// standalone piece. The root view draws these beside every compact pill
/// so the curve is identical for every activity, whatever its own view
/// does with its edges. Fits a `flare × flare` frame; the pill's wall is
/// the frame's right edge (`isLeft`) or left edge.
struct NotchEarShape: Shape {

    var isLeft: Bool

    func path(in rect: CGRect) -> Path {

        let f = rect.width
        let k = 0.5523 * f

        var path = Path()

        if isLeft {

            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.minX, y: rect.minY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - k),
                control2: CGPoint(x: rect.minX + k, y: rect.minY)
            )

        } else {

            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.maxY - k),
                control2: CGPoint(x: rect.maxX - k, y: rect.minY)
            )
        }

        path.closeSubpath()

        return path
    }
}
