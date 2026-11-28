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

    /// The notch of the Mac this runs on, read once at launch (see
    /// `NotchMetrics.configure()`); the tokens below fall back to a 14"
    /// MacBook Pro's 179 × 32 when there isn't one (an external display,
    /// a Mac without a notch). Every pill and card is laid out from these,
    /// so a narrower or wider notch — an Air's, say — gets the same fit.
    enum NotchMetrics {

        nonisolated(unsafe) static var measured: CGSize?

        @MainActor
        static func configure() {

            for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {

                guard
                    let left = screen.auxiliaryTopLeftArea,
                    let right = screen.auxiliaryTopRightArea
                else {
                    continue
                }

                let width = screen.frame.width - left.width - right.width

                if width > 0 {
                    measured = CGSize(width: width.rounded(), height: screen.safeAreaInsets.top)
                    return
                }
            }
        }
    }


    // MARK: - Shared Canvas Size
    //
    // Every activity's outer view reports THIS size, always, regardless
    // of its own actual content size — never its own compact/expanded
    // size directly. That's deliberate: the underlying AppKit window is
    // fixed and never resizes (resizing it live is where the
    // parent-recentering flakiness came from, fixed earlier for Music's
    // own compact↔expanded morph specifically). Each activity instead
    // self-positions its actual visible content within this unchanging
    // frame — same technique, just now shared across activities instead
    // of hardcoded per-activity.
    //
    // Must be at least as large as the largest content any activity
    // will ever show. Currently: Music's expanded size (390×200) sets
    // the width; FileDrop's "has items" expanded size (367×225, added
    // for the Shelf/AirDrop button reveal) sets the height.
    static var sharedCanvasSize: CGSize {
        CGSize(
            width: max(
                MusicMetrics.expandedWidth,
                FileDropMetrics.expandedWithItemsWidth,
                LauncherMetrics.clipboardWidth,
                LauncherMetrics.homeMaxWidth
            ),
            height: max(
                MusicMetrics.expandedHeight,
                FileDropMetrics.expandedWithItemsHeight,
                LauncherMetrics.notesHeight,
                LauncherMetrics.clipboardMaxHeight,
                LauncherMetrics.homeMaxHeight
            )
        )
    }

    // MARK: - Color (derived — no hex values were provided in the source files)

    enum Color {
        /// One accent per activity, per PRODUCT.md "Visual Language".
        static let musicAccent = SwiftUI.Color(red: 254/255, green: 232/255, blue: 1/255)      // measured — pixel-sampled from Trials export (#FEE801)
        static let bluetoothAccent = SwiftUI.Color(red: 0.0, green: 0.62, blue: 1.0)   // derived — blue
        static let callAccent = SwiftUI.Color(red: 0.20, green: 0.84, blue: 0.29)      // derived — green
        static let downloadsAccent = SwiftUI.Color.white                               // measured (white icon in DND/AirDrop crumb)
        static let focusAccent = SwiftUI.Color(red: 0.58, green: 0.44, blue: 0.86)     // derived — purple
        static let airDropAccent = SwiftUI.Color(red: 0.29, green: 0.62, blue: 0.98)   // derived — matches the reference screenshots' blue; not a measured hex value
        static let shelfWellBackground = SwiftUI.Color(red: 0.22, green: 0.22, blue: 0.23)  // derived — eyeballed from the shelf reference screenshot, not a measured hex value

        static let chargingAccent = SwiftUI.Color(red: 48/255, green: 209/255, blue: 88/255)   // derived — iOS system green (dark appearance), as used by the iPhone charging indicator
        static let lowBatteryAccent = SwiftUI.Color(red: 255/255, green: 69/255, blue: 58/255)   // derived — iOS system red (dark appearance), the colour of a battery at or below 20%
        static let lowPowerModeAccent = SwiftUI.Color(red: 255/255, green: 214/255, blue: 10/255) // derived — iOS system yellow, the colour of the battery while Low Power Mode is on
        static let deviceIconBackground = SwiftUI.Color(white: 1.0).opacity(0.16)              // derived — the soft grey disc behind the device icon and the Disconnect button
        static let chargingBatteryOutline = SwiftUI.Color(white: 1.0).opacity(0.35)            // derived — the dim battery shell/terminal around the green fill

        static let calendarAccent = SwiftUI.Color(red: 255/255, green: 69/255, blue: 58/255)   // derived — iOS system red, the Calendar app's tint
        static let joinAccent = SwiftUI.Color(red: 48/255, green: 209/255, blue: 88/255)       // derived — iOS system green, Calendar's "Join" button
        static let cameraIndicator = SwiftUI.Color(red: 48/255, green: 209/255, blue: 88/255)  // derived — iOS camera-in-use green
        static let microphoneIndicator = SwiftUI.Color(red: 255/255, green: 159/255, blue: 10/255) // derived — iOS microphone-in-use orange
        static let screenIndicator = SwiftUI.Color(red: 191/255, green: 90/255, blue: 242/255) // derived — iOS system purple, screen recording
        static let youtubeRed = SwiftUI.Color(red: 1.0, green: 0.0, blue: 0.0)               // YouTube's brand red
        static let pomodoroAccent = SwiftUI.Color(red: 255/255, green: 69/255, blue: 58/255)   // derived — iOS system red, a tomato
        static let timerAccent = SwiftUI.Color(red: 255/255, green: 159/255, blue: 10/255)     // derived — iOS system orange, the colour of the iPhone's timer activity
        static let capsLockAccent = SwiftUI.Color(red: 10/255, green: 132/255, blue: 255/255)  // derived — iOS system blue
        static let controlDisc = SwiftUI.Color(white: 1.0).opacity(0.18)                       // derived — grey disc behind the timer's cancel button

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
        static var compactBottomRadius: CGFloat { 12 * CGFloat(AppSettings.cornerRoundness) }

        /// How far a flat-topped pill flares out where it meets the top
        /// of the screen — the concave sweep the real notch has.
        static let notchFlare: CGFloat = 8

        /// Height the island collapses to when it leaves — the physical
        /// notch's own height. Width is `FileDropMetrics.notchWidth`.
        static var collapsedNotchHeight: CGFloat { (NotchMetrics.measured?.height ?? 32) - 3 }

        /// Rounded cards (36) or flat, notch-blended ones (0 — which also
        /// turns on the top flare). Read from Settings every time, so a
        /// change applies the next time a card is drawn.
        static var expandedTopRadius: CGFloat {
            AppSettings.expandedTopCorners == .blended ? 0 : 36 * CGFloat(AppSettings.cornerRoundness)
        }
        static var expandedBottomRadius: CGFloat { 36 * CGFloat(AppSettings.cornerRoundness) }
    }
    // MARK: - Music metrics (measured, from "ongoing music.png" + "Music Expanded.png")

    enum MusicMetrics {

        // Compact — derived from your measured notch width (179) plus two
        // symmetric flanks of 10 (edge padding) + 22 (icon) + 10 (gap to
        // notch) = 42 each. 42*2 + 179 = 263.
        static let compactWidth: CGFloat = DesignTokens.FileDropMetrics.notchWidth + 84
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
        static let expandedHeight: CGFloat = 226 // 200 + a row for the volume

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

        /// Centre-to-centre distance of the transport buttons in the
        /// expanded card — Music's measured spacing, widened a touch for
        /// the 5-second buttons.
        static let playbackButtonSpacingExpanded: CGFloat = 70

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

    // MARK: - File drop metrics (shelf + AirDrop-sending)
    //
    // The drag-hover panel (two side-by-side tiles — shelf on the left,
    // AirDrop on the right) is measured, from the "file drop
    // shelf-airdrop.png" export. The persistent shelf compact/expanded
    // sizes have no Figma yet — derived, deliberately kept close to
    // MusicMetrics' own proportions so the island doesn't visibly change
    // "weight" switching between activities. Swap for real measurements
    // the moment they exist.

    enum FileDropMetrics {

        /// The physical notch itself — per direct measurement. Used for
        /// the glow's positioning (it should visually originate from
        /// the notch's own bottom edge), distinct from
        /// `notchKeepClearWidth/Height` below (that one includes extra
        /// margin for the expanded panel's content layout; this is the
        /// bare, exact hardware dimension).
        static var notchWidth: CGFloat { NotchMetrics.measured?.width ?? 179 }
        static let notchHeight: CGFloat = 27

        /// How generous the AppKit-level drag-catch hit-region is,
        /// independent of (and much wider than) the visible pill —
        /// dragging a file doesn't need pixel-precision the way clicking
        /// the pill does. Per direct request: "generous." Height bumped
        /// from an earlier, tighter 60 — a narrow strip made the
        /// half-second "hold near the notch" glow phase genuinely hard
        /// to complete without a brief wobble resetting it (see
        /// `FileDropActivity.dragExited`'s debounce for the other half
        /// of that fix).
        static let dragCatchZoneWidth: CGFloat = 600       // derived
        static let dragCatchZoneHeight: CGFloat = 90       // derived

        // Compact — deliberately NOT independent constants. Per direct
        // question ("why doesn't the compact size match Music's?"): the
        // two were always numerically equal (263×29 both), but sharing
        // `MusicMetrics`' actual constants directly — rather than two
        // separate constants that merely happened to agree — is what
        // keeps that true by construction instead of by coincidence.
        static var compactWidth: CGFloat { DesignTokens.MusicMetrics.compactWidth }
        static var compactHeight: CGFloat = 33

        /// Before anything's been dropped yet (drag is hovering, or
        /// nothing's happened at all) — no Shelf/AirDrop buttons at this
        /// size, just the plain drop target. Measured, from the earlier
        /// "file drop shelf-airdrop.png" export.
        static let expandedEmptyWidth: CGFloat = 315
        static let expandedEmptyHeight: CGFloat = 158

        /// Once at least one file has actually been dropped — taller,
        /// to fit the Shelf/AirDrop button row at the bottom. Per direct
        /// request: buttons aren't visible until this point, and the
        /// island grows smoothly into this size when they appear.
        /// Measured, from the newer reference image.
        static let expandedWithItemsWidth: CGFloat = 367
        static let expandedWithItemsHeight: CGFloat = 225

        static let dropZoneCornerRadius: CGFloat = 24       // derived

        /// Nothing should render inside this rectangle, centered
        /// horizontally at the top of the expanded panel — it's where
        /// the physical notch cutout actually sits. Per direct
        /// measurement. Note this doesn't match `compactWidth`'s own
        /// notch-derivation above (179) — that's Music's compact-pill
        /// measurement, a different context/scale than this expanded
        /// panel's; using the number given for THIS panel specifically
        /// rather than assuming the two should agree.
        static let notchKeepClearWidth: CGFloat = 210
        static var notchKeepClearHeight: CGFloat { NotchMetrics.measured?.height ?? 32 }

        static let shelfItemSize: CGFloat = 64              // same as MusicMetrics.albumArtSize
        static let shelfItemCornerRadius: CGFloat = 16
        static let shelfGridSpacing: CGFloat = 14
        static let shelfGridPadding: CGFloat = 22           // matches MusicMetrics.expandedEdgePadding
        static let shelfWellCornerRadius: CGFloat = 22       // derived — eyeballed from the shelf reference screenshot

        /// True vertical center of the compact pill (29pt tall), used
        /// instead of `MusicMetrics.compactContentCenterY` (20) — that
        /// constant isn't actually a geometric center, it's a value
        /// tuned specifically for how Music's album art (with its own
        /// shadow/visual weight) reads best; reusing it here is what
        /// made these plain icons sit visibly low. This activity's own
        /// icons get true center instead.
        static var compactContentCenterY: CGFloat { compactHeight / 2 }

        // Bottom Shelf/AirDrop button row — only shown once the shelf
        // has items, per direct reference image. Colors are my own
        // approximation of that reference (a plain gray pill and a
        // navy-tinted one with light-blue text), not measured hex
        // values — swap if they're off.
        static let bottomButtonHeight: CGFloat = 40         // derived
        static let bottomButtonSpacing: CGFloat = 10        // derived
    }

    // MARK: - AirDrop metrics (measured, from the three AirDrop reference
    // screenshots — compact pill, expanded panel, completion checkmark)
    //
    // Both states are their own directly-measured numbers, not
    // derived/reused from Music or FileDrop's own constants — AirDrop's
    // proportions genuinely differ (259 compact width vs Music's 263, 33
    // compact height vs Music's 29).

    /// The card every "a device did something" moment shares (a Bluetooth
    /// device connecting, the sound output changing): equal 22pt edges,
    /// a 46pt glyph and a 40pt status disc, centred in the room below
    /// the notch.
    enum DeviceCard {
        static let width: CGFloat = 340
        /// Tall enough for the notch (wherever it ends) plus two lines of text.
        static var height: CGFloat { max(82, FileDropMetrics.notchKeepClearHeight + 3 + 36 + 12) }
        /// The notch only covers the middle of the top edge, so the content
        /// sits just under the top rather than below the whole notch height.
        static let topInset: CGFloat = 12
        static let edgePadding: CGFloat = 22
        static let gap: CGFloat = 14
        static let iconSize: CGFloat = 46
        static let trailingSize: CGFloat = 40
    }

    enum AirDropMetrics {

        /// Icon + ring are both 20pt, 10pt in from the pill's outer edge
        /// and 10pt in from the notch on the inner side — per direct
        /// measurement (10 + 20 + 10 = 40 per flank; 40 + notchWidth(179)
        /// + 40 = 259).
        static let compactWidth: CGFloat = DesignTokens.FileDropMetrics.notchWidth + 80
        static let compactHeight: CGFloat = 33
        static let compactIconSize: CGFloat = 20
        static let compactEdgePadding: CGFloat = 10
        static var compactContentCenterY: CGFloat { compactHeight / 2 }

        /// Icons are 42pt, 16pt in from the outer edge, 19pt from the
        /// middle title/subtitle block — per direct measurement
        /// (16 + 42 + 19 = 77 per flank).
        static let expandedWidth: CGFloat = 312
        static let expandedHeight: CGFloat = 74
        static let expandedIconSize: CGFloat = 42
        static let expandedEdgePadding: CGFloat = 16
        static let expandedIconToTextGap: CGFloat = 19

        /// Progress ring stroke — derived, not present in the reference
        /// exports; proportioned to read clearly at both the 20pt
        /// compact and 42pt expanded ring sizes.
        static let ringLineWidth: CGFloat = 2.5

        /// Completion checkmark — matches the third reference image (a
        /// solid black circle, thin light stroke, white checkmark).
        /// Shown only at compact size, per direct confirmation.
        static let checkmarkStrokeOpacity: Double = 0.9
    }

    // MARK: - Charging metrics
    //
    // Compact-only pill, shown for a few seconds when the charger is
    // plugged in. Follows the same construction as the other compact
    // pills — fixed notch in the middle, a flank on each side, 10pt
    // edge padding, 33pt tall like the AirDrop/FileDrop pills — just
    // with wider flanks, because "Charging" and "100%" + battery need
    // more room than a 20pt icon.
    //
    // Flank widths are DERIVED, not measured: 10 edge + content + 10 gap
    // to the notch. Left content ("Charging", 12pt semibold) is ~50pt;
    // right content (percentage + battery) is ~59pt. The "Not Charging"
    // label shown on unplug is ~72pt, so the flank is sized for that
    // (10 + 72 + 6). Both flanks use the same width so the pill stays
    // visually centered on the notch.

    enum ChargingMetrics {

        static let compactEdgePadding: CGFloat = 10
        static let flankWidth: CGFloat = 88
        static let compactWidth: CGFloat = DesignTokens.FileDropMetrics.notchWidth + flankWidth * 2   // 179 + 176 = 355
        static let compactHeight: CGFloat = 33

        // Typography — SF Pro (system), semibold, same family as every
        // other string in the island.
        static let labelFont = Font.system(size: 12, weight: .semibold)
        static let percentFont = Font.system(size: 12, weight: .semibold)
        static let percentToBatterySpacing: CGFloat = 5

        // Battery glyph (iPhone status-bar proportions, ~25×12 overall)
        static let batteryBodyWidth: CGFloat = 22
        static let batteryBodyHeight: CGFloat = 12
        static let batteryBodyCornerRadius: CGFloat = 3.5
        static let batteryOutlineWidth: CGFloat = 1
        static let batteryFillInset: CGFloat = 1.5
        static let batteryFillCornerRadius: CGFloat = 2
        static let batteryFillMinWidth: CGFloat = 2
        /// Inner width available to the fill: body minus outline/inset on both sides.
        static let batteryFillMaxWidth: CGFloat = batteryBodyWidth - batteryFillInset * 2
        static let batteryCapWidth: CGFloat = 1.5
        static let batteryCapHeight: CGFloat = 4.5
        static let batteryCapSpacing: CGFloat = 0.5
        static let batteryBoltSize: CGFloat = 7
    }

    // MARK: - Low battery metrics
    //
    // Same construction as the charging pill (notch in the middle, a
    // flank each side, 10pt edge padding, 33pt tall), but wider: the
    // right flank holds a "Low Power Mode" button (~98pt incl. padding),
    // which "Charging"'s flank never had to fit. Flank width is DERIVED:
    // 10 edge + ~98 button + a few points of breathing room to the notch.
    // This is wider than the shared canvas (390), so `LowBatteryIslandView`
    // sizes its own canvas instead of `sharedCanvasSize` — the shared
    // constant is read by the shelf and must stay exactly as it was.

    enum LowBatteryMetrics {

        static let compactEdgePadding: CGFloat = 10
        static let flankWidth: CGFloat = 116
        static let compactWidth: CGFloat = DesignTokens.FileDropMetrics.notchWidth + flankWidth * 2   // 179 + 232 = 411
        static let compactHeight: CGFloat = 33

        static let percentFont = Font.system(size: 12, weight: .semibold)
        static let buttonFont = Font.system(size: 11, weight: .semibold)
        static let percentToBatterySpacing: CGFloat = 5

        static let buttonHorizontalPadding: CGFloat = 9
        static let buttonHeight: CGFloat = 22
        static let confirmationIconSpacing: CGFloat = 4

        /// The strip of Bluetooth batteries under the alert.
        static let deviceRowHeight: CGFloat = 30
        static let ringSize: CGFloat = 22
    }

    // MARK: - Bluetooth metrics
    //
    // Compact uses AirDrop's measured pill (`AirDropMetrics`). Expanded
    // follows AirDrop's expanded proportions (16pt edge, 42pt icon) but
    // is wider and taller: wider because it holds a Disconnect button
    // as well as the name, taller so the content sits entirely below
    // the physical notch (32pt keep-clear) instead of behind it.
    // Sizes below are DERIVED from those, not separately measured.

    enum BluetoothMetrics {

        static let expandedWidth: CGFloat = 360
        static let expandedHeight: CGFloat = 96

        static let edgePadding: CGFloat = 20
        static let iconSize: CGFloat = 48
        static let iconToTextGap: CGFloat = 12
        static let bottomPadding: CGFloat = 10

        static let statusFont = Font.system(size: 13, weight: .medium)
        static let buttonFont = Font.system(size: 13, weight: .semibold)
        static let buttonHeight: CGFloat = 32
        static let buttonHorizontalPadding: CGFloat = 16
    }

    // MARK: - Timer metrics
    //
    // Compact: notch in the middle, a wider right flank for "1:24:59".
    // Expanded: big time on the left, cancel + pause/resume discs on the
    // right, all below the physical notch. Sizes are DERIVED from the
    // Bluetooth pill's proportions, not separately measured.

    enum TimerMetrics {

        static let compactEdgePadding: CGFloat = 10
        /// Both flanks match so the notch stays centred; sized for the
        /// widest label, "1:24:59". The dual layout (timer left,
        /// stopwatch right) needs a glyph beside each time.
        /// Flanks hug their content, like the iPhone's timer pill: just
        /// room for "m:ss" (or "h:mm:ss" from an hour up), and for two
        /// glyph+time pairs when two clocks run.
        static let flankWidth: CGFloat = 50
        static let flankWidthHours: CGFloat = 66
        static let flankWidthDual: CGFloat = 70
        static let flankWidthDualHours: CGFloat = 88
        static let compactHeight: CGFloat = 33

        /// Compact glyphs follow the other 33pt pills (AirDrop /
        /// Bluetooth): a 20pt slot with the symbol drawn at 14pt, so it
        /// reads at the same visual weight as the 13pt time beside it.
        static let compactIconSlot: CGFloat = 20
        static let compactGlyphSize: CGFloat = 14
        static let compactTimeFont = Font.system(size: 13, weight: .semibold)
        static let compactGlyphToTime: CGFloat = 5

        /// Split layout (timer on the left of the notch, another
        /// activity on the right): room for "m:ss" / "h:mm:ss".
        static let splitTimeWidth: CGFloat = 38
        static let splitTimeWidthHours: CGFloat = 56
        static let splitNotchPadding: CGFloat = 8

        static let expandedWidth: CGFloat = 360
        static let expandedHeight: CGFloat = 112
        /// Extra room under a running Pomodoro for its sound controls.
        static let soundBarHeight: CGFloat = 30
        /// Notch keep-clear + bottom padding; each row of a multi-clock
        /// panel then adds `expandedRowHeightDual`.
        static let expandedHeaderHeight: CGFloat = 40
        static let expandedRowHeightDual: CGFloat = 60
        static let expandedEdgePadding: CGFloat = 22
        static let bottomPadding: CGFloat = 8
        static let rowSpacing: CGFloat = 4

        static let timeFont = Font.system(size: 38, weight: .light)
        static let timeFontDual = Font.system(size: 28, weight: .light)
        static let labelFont = Font.system(size: 12, weight: .semibold)
        static let labelGlyphSize: CGFloat = 11

        static let buttonSize: CGFloat = 44
        static let buttonSizeDual: CGFloat = 36
        static let buttonSpacing: CGFloat = 12
        static let buttonGlyphSize: CGFloat = 17
        static let buttonGlyphSizeDual: CGFloat = 14
    }

    // MARK: - Minimal bubble metrics
    //
    // The detached circle beside the island — a second activity's
    // "minimal" presentation, or the privacy dot. Same height as the
    // compact pills so the two read as one row.

    enum BubbleMetrics {

        /// A rounded square, not a circle, so it reads as part of the
        /// island rather than a floating dot.
        static let side: CGFloat = 26
        static let cornerRadius: CGFloat = 8

        /// Centred in the 33pt pill height — never touching the top.
        static let topInset: CGFloat = (33 - side) / 2

        /// Gap to the notch edge when the bubble sits right beside the
        /// notch (the timer's split layout), and to a pill's edge when
        /// it sits beside a full pill.
        static let notchGap: CGFloat = 2
        static let pillGap: CGFloat = 5

        static let contentSize: CGFloat = 18
        static let contentCornerRadius: CGFloat = 5.5
        static let glyphSize: CGFloat = 11
        static let ringLineWidth: CGFloat = 2.2
    }

    // MARK: - Status pill metrics
    //
    // The shared compact pill for short status moments (calendar,
    // privacy, downloads): a glyph on the left, a short label on the
    // right, with a flank just wide enough for "10 min" / "Camera".

    enum StatusPillMetrics {
        static let flankWidth: CGFloat = 56
        static let compactWidth: CGFloat = DesignTokens.FileDropMetrics.notchWidth + flankWidth * 2
        static let compactHeight: CGFloat = 33
        static let edgePadding: CGFloat = 10
        static let iconSlot: CGFloat = 20
        static let glyphSize: CGFloat = 14
        static let labelFont = Font.system(size: 12, weight: .semibold)
    }

    // MARK: - Calendar metrics (expanded; compact is `StatusPillMetrics`)

    enum CalendarMetrics {
        static let expandedWidth: CGFloat = 360
        static let expandedHeight: CGFloat = 96
        static let edgePadding: CGFloat = 20
        static let iconSize: CGFloat = 48
        static let iconToTextGap: CGFloat = 12
        static let bottomPadding: CGFloat = 10
        static let subtitleFont = Font.system(size: 13, weight: .medium)
        static let buttonFont = Font.system(size: 13, weight: .semibold)
        static let buttonHeight: CGFloat = 32
        static let buttonHorizontalPadding: CGFloat = 18
    }

    // MARK: - Downloads metrics (expanded; compact is `StatusPillMetrics`)

    enum DownloadsMetrics {
        static let expandedWidth: CGFloat = 380
        static let expandedHeight: CGFloat = 92
        static let edgePadding: CGFloat = 20
        static let ringSize: CGFloat = 48
        static let ringLineWidth: CGFloat = 3
        static let compactRingLineWidth: CGFloat = 2.5
        static let iconToTextGap: CGFloat = 14
        static let bottomPadding: CGFloat = 10
        static let subtitleFont = Font.system(size: 13, weight: .medium)
        static let buttonSize: CGFloat = 34
        static let buttonGlyphSize: CGFloat = 14
        static let buttonSpacing: CGFloat = 8
    }

    // MARK: - Launcher metrics
    //
    // The menu that opens when the empty notch is clicked. Width stays
    // inside the shared canvas (390). Sizes are DERIVED from the Music
    // expanded panel's proportions (22pt edge, 64pt art tile scaled down).

    enum LauncherMetrics {

        /// The Timer and Pomodoro setup pages: the launcher's original size.
        static let width: CGFloat = 380
        static let height: CGFloat = 220

        /// The home page carries five tiles, so it's a touch wider.
        static let homeWidth: CGFloat = 420
        static let homeHeight: CGFloat = 228

        /// The clipboard is as tall as what's in it (up to `clipboardMaxRows`).
        static let clipboardWidth: CGFloat = 420
        static let clipboardRowHeight: CGFloat = 46
        static let clipboardMaxRows = 5
        static let clipboardChrome: CGFloat = 32 + 34 + 8 + 16   // notch + header + gap + bottom
        static let clipboardEmptyHeight: CGFloat = 150
        static let clipboardMaxHeight: CGFloat = clipboardChrome + CGFloat(clipboardMaxRows) * clipboardRowHeight

        static let toolsHeight: CGFloat = 268
        static let cameraWidth: CGFloat = 420
        static let cameraHeight: CGFloat = 300
        static let activityWidth: CGFloat = 420
        static let activityHeight: CGFloat = 212

        static let notesWidth: CGFloat = 420
        static let notesHeight: CGFloat = 348

        /// The home page with no Bluetooth device row (its height plus
        /// the spacing above it).
        static let heightWithoutDevice: CGFloat = homeHeight - sectionSpacing - deviceCardHeight

        /// The home page at its fullest: two running clocks and the battery
        /// rings (the canvas has to fit it, or its bottom would be cut).
        static let homeMaxWidth: CGFloat = homeWidth
        static let homeMaxHeight: CGFloat = heightWithoutDevice
            + 2 * (timerRowHeight + sectionSpacing)
            + sectionSpacing + deviceCardHeight


        static let edgePadding: CGFloat = 20
        static let bottomPadding: CGFloat = 16
        static let sectionSpacing: CGFloat = 12


        static let artSize: CGFloat = 48
        static let artCornerRadius: CGFloat = 11
        static let transportButtonSize: CGFloat = 40

        static let tileHeight: CGFloat = 54

        static let deviceCardHeight: CGFloat = 42
        static let timerRowHeight: CGFloat = 34
        static let tileSpacing: CGFloat = 10
        static let tileCornerRadius: CGFloat = 16   // concentric: 36pt panel radius - 20pt edge padding
        static let tileGlyphSize: CGFloat = 19

        static let chipHeight: CGFloat = 32
        static let controlSize: CGFloat = 34
        static let startButtonHeight: CGFloat = 34

        static let titleFont = Font.system(size: 15, weight: .semibold)
        static let subtitleFont = Font.system(size: 13, weight: .medium)
        static let tileFont = Font.system(size: 12, weight: .semibold)
        static let valueFont = Font.system(size: 17, weight: .semibold)
    }

    // MARK: - Caps Lock metrics (same pill as AirDrop/Bluetooth compact)

    enum CapsLockMetrics {
        static let statusFont = Font.system(size: 13, weight: .semibold)
        /// Symbol drawn inside the 20pt compact icon slot — same size as
        /// the timer's glyphs so the two pills read alike.
        static let glyphSize: CGFloat = 14
    }

    // MARK: - Hover affordance shadow (new — additive only, nothing above
    // this line was touched)
    //
    // The instant, no-delay "I noticed you" cue shown the moment a hover
    // begins, before the separately-timed expand actually commits. Values
    // are derived to read as a soft elevation lift, not a hard drop shadow.

    enum Shadow {
        /// Resting (compact) island: a soft ambient shadow plus a tight
        /// contact shadow, the way Apple lifts the Dynamic Island off the
        /// content behind it.
        /// The activity-colour glow around a compact pill: faint at rest,
        /// prominent on hover (while the card is about to open).
        static let accentRestOpacity: Double = 0.2
        static let accentHoverOpacity: Double = 0.62
        /// Open card: a little above the resting level, no more.
        static let accentExpandedOpacity: Double = 0.3
        static let accentExpandedRadius: CGFloat = 22
        static let accentRestRadius: CGFloat = 9
        static let accentHoverRadius: CGFloat = 16

        static let restOpacity: Double = 0.34
        static let hoverOpacity: Double = 0.48
        static let expandedOpacity: Double = 0.55
        static let restColor = SwiftUI.Color.black.opacity(restOpacity)
        static let restRadius: CGFloat = 8
        static let restYOffset: CGFloat = 3

        /// The stronger "noticed you" shadow the instant a hover begins.
        static let hoverColor = SwiftUI.Color.black.opacity(0.48)
        static let hoverRadius: CGFloat = 14
        static let hoverYOffset: CGFloat = 6

        /// Expanded island: the island floats well above the content, so
        /// the shadow is larger, softer and lower.
        static let expandedColor = SwiftUI.Color.black.opacity(0.55)
        static let expandedRadius: CGFloat = 26
        static let expandedYOffset: CGFloat = 12

        /// Always-on tight shadow hugging the edge — gives the pill a
        /// crisp edge against light wallpapers.
        static let contactColor = SwiftUI.Color.black.opacity(0.28)
        static let contactRadius: CGFloat = 2.5
        static let contactYOffset: CGFloat = 1

        /// Extra transparent room carved around the visible pill so the
        /// shadows above have somewhere to render into. AppKit clips all
        /// drawing to the window's frame. No top inset: the pill's top
        /// edge must stay flush with the physical screen top (the notch).
        static let canvasInsetX: CGFloat = expandedRadius + 4
        static let canvasInsetBottom: CGFloat = expandedRadius + expandedYOffset + 4
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
