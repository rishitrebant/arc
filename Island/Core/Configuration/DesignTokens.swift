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
        static let title = Font.system(size: 17, weight: .bold, design: .default)       // heavier — visual anchor of the header
        static let titleRegular = Font.system(size: 17, weight: .regular, design: .default) // Call name uses Regular 17
        static let subtitle = Font.system(size: 11, weight: .regular, design: .default) // secondary via size + color, not a thin weight
        static let timestamp = Font.system(size: 12, weight: .regular, design: .default)   // SF Pro Text Regular 12
        static let letterSpacingTight: CGFloat = -0.41 // measured, applied via .tracking()
    }

    // MARK: - Island shape (confirmed against Figma layer inspector)

    enum Shape {
        /// The island body is flush/square where it meets the physical
        /// notch (top) and rounded only where it "hangs" below it (bottom).
        /// Confirmed directly against the Figma layer inspector — these are
        /// no longer estimates.
        static let compactTopRadius: CGFloat = 0     // confirmed
        static let compactBottomRadius: CGFloat = 12  // confirmed
        static let expandedTopRadius: CGFloat = 0     // confirmed
        static let expandedBottomRadius: CGFloat = 48 // confirmed
    }

    // MARK: - Music metrics (measured, from "ongoing music.png" + "Music Expanded.png")

    enum MusicMetrics {
        // Compact
        static let compactWidth: CGFloat = 298       // measured
        /// Locked at exactly 38pt — confirmed Figma measurement. Do not
        /// adjust; the notch-extension feel comes from the flush-top shape
        /// and correct radius, not from shrinking this number further.
        static let compactHeight: CGFloat = 38        // confirmed
        static let compactIconSize: CGFloat = 24      // measured
        static let compactIconCornerRadius: CGFloat = 6 // confirmed (Figma inspector)

        // Expanded
        static let expandedWidth: CGFloat = 390      // measured
        static let expandedHeight: CGFloat = 200      // measured
        static let expandedEdgePadding: CGFloat = 24  // measured — used for sides + bottom
        /// The physical notch's exclusion zone, measured directly off the
        /// "Notch" annotation in the Figma reference: y:0-48, x:94-303
        /// relative to the card. Content must clear the full 48pt height —
        /// horizontal position isn't a safe way to dodge it since notch
        /// width varies by hardware. This is why top padding is larger than
        /// the side/bottom padding, not a mistake.
        static let expandedTopPadding: CGFloat = 48    // measured (Figma "Notch" annotation)
        /// Nudged down from the measured 65pt — slightly smaller reads
        /// closer to Apple's own proportions without abandoning the Figma
        /// baseline.
        static let albumArtSize: CGFloat = 56          // derived (measured value was 65)
        static let albumArtCornerRadius: CGFloat = 16 // measured
        static let progressBarWidth: CGFloat = 242    // measured
        static let playbackRowWidth: CGFloat = 101.3  // measured
        static let playbackButtonSpacing: CGFloat = 38 // measured
        static let waveformIconWidth: CGFloat = 43     // measured
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
