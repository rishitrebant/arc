import SwiftUI

/// The charging battery drawn on the right of the pill: outlined body,
/// rounded fill proportional to the charge level, a small terminal cap,
/// and a lightning bolt centred on top — the same construction as the
/// iPhone's status-bar battery while charging.
///
/// Drawn rather than using an SF Symbol so the fill level is exact and
/// the green matches the percentage text.
struct BatteryGlyph: View {

    /// 0...100
    let percent: Int

    /// Fill colour. Green while charging, red when low, yellow in
    /// Low Power Mode.
    var tint: Color = DesignTokens.Color.chargingAccent

    /// The bolt is only for the charging state.
    var showsBolt: Bool = true

    private typealias Metrics = DesignTokens.ChargingMetrics

    private var fillFraction: CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }

    var body: some View {

        HStack(spacing: Metrics.batteryCapSpacing) {

            ZStack(alignment: .leading) {

                // Body outline
                RoundedRectangle(
                    cornerRadius: Metrics.batteryBodyCornerRadius,
                    style: .continuous
                )
                .stroke(
                    DesignTokens.Color.chargingBatteryOutline,
                    lineWidth: Metrics.batteryOutlineWidth
                )

                // Charge fill
                RoundedRectangle(
                    cornerRadius: Metrics.batteryFillCornerRadius,
                    style: .continuous
                )
                .fill(tint)
                .frame(
                    width: max(
                        Metrics.batteryFillMinWidth,
                        Metrics.batteryFillMaxWidth * fillFraction
                    )
                )
                .padding(Metrics.batteryFillInset)

                // Bolt
                if showsBolt {
                    Image(systemName: "bolt.fill")
                        .font(.system(
                            size: Metrics.batteryBoltSize,
                            weight: .bold
                        ))
                        .foregroundStyle(.white)
                        .frame(
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                }
            }
            .frame(
                width: Metrics.batteryBodyWidth,
                height: Metrics.batteryBodyHeight
            )

            // Terminal cap
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: Metrics.batteryCapWidth,
                topTrailingRadius: Metrics.batteryCapWidth,
                style: .continuous
            )
            .fill(DesignTokens.Color.chargingBatteryOutline)
            .frame(
                width: Metrics.batteryCapWidth,
                height: Metrics.batteryCapHeight
            )
        }
    }
}
