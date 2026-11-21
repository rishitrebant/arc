import SwiftUI

/// The device icon: a plain SF Symbol, the way Apple's own connect
/// moments draw it — flat, white, nothing faked.
///
/// Compact pill: just the glyph. Expanded panel: the glyph centred on a
/// soft grey disc (the same disc the island's other buttons use).
struct DeviceIconView: View {

    let symbolName: String
    let diameter: CGFloat

    /// Compact pill: just the glyph. Expanded panel: glyph on the disc.
    var showsDisc: Bool = true

    var body: some View {

        ZStack {

            if showsDisc {
                Circle()
                    .fill(DesignTokens.Color.deviceIconBackground)
            }

            Image(systemName: symbolName)
                .symbolRenderingMode(.hierarchical)
                .font(.system(
                    size: diameter * (showsDisc ? 0.44 : 0.74),
                    weight: .medium
                ))
                .foregroundStyle(DesignTokens.Color.primaryText)
        }
        .frame(width: diameter, height: diameter)
    }
}
