import AppKit

/// The physical notch, measured rather than assumed.
///
/// macOS reports it on the built-in screen: the safe-area inset at the top
/// is the notch's height, and the two menu-bar areas either side of it
/// leave exactly the notch's width between them. (A 14" MacBook Pro's is
/// 179 × 32; other models differ.) Screens without a notch — external
/// displays — fall back to the design tokens' values.
@MainActor
enum NotchGeometry {

    /// Width and height of the notch, in points.
    static var size: CGSize {

        for screen in NSScreen.screens where screen.safeAreaInsets.top > 0 {

            guard
                let left = screen.auxiliaryTopLeftArea,
                let right = screen.auxiliaryTopRightArea
            else {
                continue
            }

            let width = screen.frame.width - left.width - right.width

            if width > 0 {
                return CGSize(width: width, height: screen.safeAreaInsets.top)
            }
        }

        return CGSize(
            width: DesignTokens.FileDropMetrics.notchWidth,
            height: DesignTokens.FileDropMetrics.notchKeepClearHeight
        )
    }

    /// Extra room around the notch that still counts as "on the notch"
    /// for hovering and clicking. The cursor slips behind the notch, so a
    /// target exactly its size is fiddly to land on.
    static let hoverMarginX: CGFloat = 28
    static let hoverMarginY: CGFloat = 10

    /// Half-width / height of the hover and click target.
    static var targetHalfWidth: CGFloat { size.width / 2 + hoverMarginX }
    static var targetHeight: CGFloat { size.height + hoverMarginY }
}
