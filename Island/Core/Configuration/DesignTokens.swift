import SwiftUI

/// Centralized design constants.
///
/// Per Engineering Constitution: "Magic numbers are prohibited."
/// Every spacing, radius, color, and size value used by any Activity or
/// UI component must be sourced from here — never hardcoded in a View.
///
/// SOURCE NOTES:
/// Values marked "measured" come directly from
/// `Figma exports/Measurements/*.png`.
/// Values marked "derived" were not present in any Figma export and were
/// chosen to feel consistent with the measured values and Apple's own
/// Dynamic Island. These should be treated as placeholders — swap them
/// for real design values the moment they exist.
enum DesignTokens {

    // MARK: - Color (derived — no hex values were provided in the source files)

    enum Color {
        /// One accent per activity, per PRODUCT.md "Visual Language".
        static let musicAccent = SwiftUI.Color(red: 254/255, green: 232/255, blue: 1/255)      // measured — pixel-sampled from Trials export (#FEE801)
        static let bluetoothAccent = SwiftUI.Color(red: 0.0, green: 0.62, blue: 1.0)   // derived — blue
        static let callAccent = SwiftUI.Color(red: 0.20, green: 0.84, blue: 0.29)      // derived — green
        static let downloadsAccent = SwiftUI.Color.white                               // measured (white icon in DND/AirDrop crumb)
        static let focusAccent = SwiftUI.Color(red: 0.58, green: 0.44, blue: 0.86)     // derived — purple

        static let islandBackground = SwiftUI.Color.black                              // measured — pure black surface
        static let primaryText = SwiftUI.Color(white: 1.0)                             // measured — #FFFFFF
        static let secondaryText = SwiftUI.Color(white: 0.6)                           // measured — #999999
        static let tertiaryText = SwiftUI.Color(white: 0.44)                           // measured — #707070 (call subtitle)
    }

    // MARK: - Typography (measured, from Music Expanded + Call Expanded annotations)

    enum Typography {
        static let title = Font.system(size: 17, weight: .semibold)
        static let titleRegular = Font.system(size: 17, weight: .regular)
        static let subtitle = Font.system(size: 11, weight: .regular)
        static let timestamp = Font.system(size: 12, weight: .regular)

        static let letterSpacingTight: CGFloat = -0.25
    }

    // MARK: - Island shape (confirmed against Figma layer inspector)

    enum Shape {
        static let compactTopRadius: CGFloat = 32
        static let compactBottomRadius: CGFloat = 32

        static let expandedTopRadius: CGFloat = 48
        static let expandedBottomRadius: CGFloat = 48
    }
    // MARK: - Music metrics (measured, from "ongoing music.png" + "Music Expanded.png")

    enum MusicMetrics {

        // Compact
        static let compactWidth: CGFloat = 298
        static let compactHeight: CGFloat = 38

        static let compactIconSize: CGFloat = 22
        static let compactIconCornerRadius: CGFloat = 6

        // Expanded
        static let expandedWidth: CGFloat = 390
        static let expandedHeight: CGFloat = 188

        static let expandedEdgePadding: CGFloat = 22
        static let expandedTopPadding: CGFloat = 44

        static let albumArtSize: CGFloat = 52
        static let albumArtCornerRadius: CGFloat = 14

        static let progressBarWidth: CGFloat = 242

        static let playbackRowWidth: CGFloat = 104
        static let playbackButtonSpacing: CGFloat = 34

        static let waveformIconWidth: CGFloat = 34
    }

    // MARK: - Call metrics (measured, from "Expanded Callpng.png")

    enum CallMetrics {
        static let expandedWidth: CGFloat = 405        // measured
        static let expandedHeight: CGFloat = 158        // measured
        static let avatarSize: CGFloat = 50             // measured
        static let controlSpacing: CGFloat = 25         // measured
    }

    // MARK: - Generic spacing scale (8pt / 16pt system)

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 16
        static let md: CGFloat = 24
        static let lg: CGFloat = 32
    }
}
