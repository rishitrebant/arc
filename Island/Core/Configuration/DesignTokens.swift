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
        static let compactTopRadius: CGFloat = 0
        static let compactBottomRadius: CGFloat = 12

        static let expandedTopRadius: CGFloat = 18
        static let expandedBottomRadius: CGFloat = 18
    }
    // MARK: - Music metrics (measured, from "ongoing music.png" + "Music Expanded.png")

    enum MusicMetrics {

        // Compact — derived from your measured notch width (179) plus two
        // symmetric flanks of 10 (edge padding) + 22 (icon) + 10 (gap to
        // notch) = 42 each. 42*2 + 179 = 263.
        static let compactWidth: CGFloat = 263
        static let compactHeight: CGFloat = 29
        static let compactContentCenterY: CGFloat = 20

        static let compactIconSize: CGFloat = 22
        static let compactIconCornerRadius: CGFloat = 4

        /// Distance from the pill's outer edge to the icon/waveform — NOT
        /// the same as `Spacing.sm` (16), which other views still use.
        /// Kept separate on purpose so tuning the compact pill never
        /// silently moves spacing anywhere else.
        static let compactEdgePadding: CGFloat = 10

        static let waveformBarCount: Int = 6
        static let waveformBarSpacing: CGFloat = 1.83

        // Expanded
        static let expandedWidth: CGFloat = 390 
        static let expandedHeight: CGFloat = 200 // was 188

        static let expandedEdgePadding: CGFloat = 22
        static let expandedTopPadding: CGFloat = 44

        static let albumArtSize: CGFloat = 64
        static let albumArtCornerRadius: CGFloat = 16

        static let progressBarWidth: CGFloat = 242

        /// Center-to-center distance between adjacent transport buttons
        /// (prev↔pause, pause↔next) — measured, not guessed. Replaces the
        /// old 34, which produced 77/71pt gaps that never matched any
        /// real reference.
        static let playbackButtonSpacing: CGFloat = 41

        /// Gap from the forward button's right edge to the AirPlay icon's
        /// left edge — measured, but NOT what actually positions AirPlay
        /// (see `MusicIslandView.airplayCenter`, which uses its own
        /// directly-measured center instead — the two don't fully
        /// reconcile; see that file's comment for the ~35pt discrepancy
        /// this gap alone couldn't explain). Kept as a named constant
        /// since it's still real, measured data, even if unused for now.
        static let airplayGap: CGFloat = 43
        static let airplayIconSize: CGFloat = 23

        static let waveformIconWidth: CGFloat = 34

        /// Fraction of the waveform's bounding box left empty on each
        /// side as breathing room around the bars ("thinner, shorter" per
        /// feedback). This is an ESTIMATE, not a measurement — there was
        /// no exact number given for how much smaller the bars should
        /// read relative to their slot. Tell me the real number if you
        /// have one and I'll swap this for it directly.
        static let waveformContentInset: CGFloat = 0.15
    }

    // MARK: - Call metrics (measured, from "Expanded Callpng.png")

    enum CallMetrics {
        static let expandedWidth: CGFloat = 405        // measured
        static let expandedHeight: CGFloat = 158        // measured
        static let avatarSize: CGFloat = 50             // measured
        static let controlSpacing: CGFloat = 25         // measured
    }

    // MARK: - Hover affordance shadow (new — additive only, nothing above
    // this line was touched)
    //
    // The instant, no-delay "I noticed you" cue shown the moment a hover
    // begins, before the separately-timed expand actually commits. Values
    // are derived to read as a soft elevation lift, not a hard drop shadow.

    enum Shadow {
        /// Always present, subtle — real macOS UI elements (menu bar
        /// items, widgets) generally carry a soft resting shadow, not just
        /// an on-hover one. This is that baseline.
        static let restColor = SwiftUI.Color.black.opacity(0.28)
        static let restRadius: CGFloat = 6
        static let restYOffset: CGFloat = 3

        /// The stronger "noticed you" shadow layered on top the instant a
        /// hover begins — same shadow, more pronounced, not a different
        /// effect.
        static let hoverColor = SwiftUI.Color.black.opacity(0.45)
        static let hoverRadius: CGFloat = 16
        static let hoverYOffset: CGFloat = 8

        /// Extra transparent room carved around the visible pill so the
        /// shadow above has somewhere to render into. AppKit clips all
        /// drawing to the window's frame — a window sized exactly to the
        /// pill (as it was) clips the shadow to nothing before it's ever
        /// visible, regardless of how correct the SwiftUI shadow code is.
        /// `WindowManager` builds the real window frame from the pill size
        /// *plus* these insets, and pads the SwiftUI content by the same
        /// amount so the pill still sits exactly where it should inside
        /// the larger, invisible canvas. No top inset: the pill's top
        /// edge must stay flush with the physical screen top (the notch
        /// itself), so there's nowhere for a shadow to bleed upward into
        /// regardless — and nothing is lost, since that direction is
        /// covered by the camera housing in real life anyway.
        static let canvasInsetX: CGFloat = hoverRadius + 4
        static let canvasInsetBottom: CGFloat = hoverRadius + hoverYOffset + 4
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
