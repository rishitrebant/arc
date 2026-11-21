import SwiftUI

/// The device icon, drawn to feel dimensional rather than flat — the
/// closest a Mac app can get to the 3D device renders iOS shows for
/// AirPods without shipping Apple's artwork.
///
/// Depth comes from four cheap, static layers (no 3D engine, no
/// animation loop, so no ongoing energy cost):
///   1. a disc lit from the top-left (radial gradient),
///   2. a thin rim light that fades from top to bottom,
///   3. a soft specular highlight across the upper half,
///   4. the glyph itself with a top-to-bottom gradient and a short
///      drop shadow, so it sits above the disc instead of on it.
struct DeviceIconView: View {

    let symbolName: String
    let diameter: CGFloat

    /// Compact pill: just the lit glyph. Expanded panel: glyph on the disc.
    var showsDisc: Bool = true

    var body: some View {

        ZStack {

            if showsDisc {
                disc
            }

            Image(systemName: symbolName)
                .font(.system(
                    size: diameter * (showsDisc ? 0.46 : 0.78),
                    weight: .semibold
                ))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color.white,
                            Color(white: 0.70)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(
                    color: Color.black.opacity(0.55),
                    radius: diameter * 0.05,
                    x: 0,
                    y: diameter * 0.04
                )
        }
        .frame(width: diameter, height: diameter)
    }

    private var disc: some View {

        ZStack {

            // 1. Body — lit from the top-left.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(white: 0.36),
                            Color(white: 0.11)
                        ],
                        center: UnitPoint(x: 0.3, y: 0.2),
                        startRadius: 0,
                        endRadius: diameter * 0.95
                    )
                )

            // 2. Rim light.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.50),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.75
                )

            // 3. Specular highlight.
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.26),
                            Color.white.opacity(0.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: diameter * 0.72, height: diameter * 0.40)
                .offset(y: -diameter * 0.27)
        }
        .shadow(
            color: Color.black.opacity(0.6),
            radius: diameter * 0.09,
            x: 0,
            y: diameter * 0.05
        )
    }
}
