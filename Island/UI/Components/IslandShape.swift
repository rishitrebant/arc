import SwiftUI

enum IslandShape {

    static func body(
        topRadius: CGFloat,
        bottomRadius: CGFloat
    ) -> UnevenRoundedRectangle {

        UnevenRoundedRectangle(
            topLeadingRadius: topRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: topRadius,
            style: .continuous
        )

    }

}
