import SwiftUI
import AppKit

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

// MARK: - 3D device artwork

/// macOS ships rendered (3D) artwork for a few devices — AirPods, Beats,
/// the Magic Mouse, a speaker. Used where one fits; anything else gets a
/// dimensional take on its SF Symbol (see `Device3DIcon`).
enum DeviceArtwork {

    private static let bluetoothUI =
        "/System/Library/Frameworks/IOBluetoothUI.framework/Versions/A/Resources/"

    private static let coreTypes =
        "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/"

    private static var cache: [String: NSImage] = [:]

    static func image(name: String, symbolName: String) -> NSImage? {

        let lowered = name.lowercased()

        let path: String?

        if lowered.contains("airpods max") {
            path = nil
        } else if lowered.contains("airpods") {
            path = bluetoothUI + "AirPods.png"
        } else if lowered.contains("powerbeats") {
            path = bluetoothUI + "Powerbeats3.png"
        } else if lowered.contains("beats solo") {
            path = bluetoothUI + "BeatsSolo3.png"
        } else if lowered.contains("beatsx") || lowered.contains("beats x") {
            path = bluetoothUI + "BeatsX.png"
        } else if symbolName == "hifispeaker.fill" || lowered.contains("speaker") {
            path = coreTypes + "GenericSpeaker.icns"
        } else if lowered.contains("mouse") {
            path = bluetoothUI + "MightyMouse.icns"
        } else {
            path = nil
        }

        guard let path else { return nil }

        if let cached = cache[path] { return cached }

        guard let image = NSImage(contentsOfFile: path) else { return nil }

        cache[path] = image

        return image
    }
}

/// A device's icon with some depth: the system's rendered artwork when
/// there is some, otherwise its symbol with a gradient, a soft highlight
/// and a drop shadow.
struct Device3DIcon: View {

    let symbolName: String
    let name: String
    let size: CGFloat

    var body: some View {

        Group {

            if let artwork = DeviceArtwork.image(name: name, symbolName: symbolName) {

                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: size, height: size)

            } else {

                Image(systemName: symbolName)
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: size * 0.8, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.62)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    // A thin light edge along the top, like a lit bevel.
                    .shadow(color: Color.white.opacity(0.35), radius: 0, x: 0, y: -0.6)
                    .frame(width: size, height: size)
            }
        }
        .shadow(color: Color.black.opacity(0.55), radius: size * 0.08, x: 0, y: size * 0.05)
        .frame(width: size, height: size)
    }
}
