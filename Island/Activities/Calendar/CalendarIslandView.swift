import SwiftUI

/// Renders `CalendarActivity`:
///   - compact: a red calendar glyph on the left, the countdown
///     ("5 min", "Now") on the right
///   - expanded (on hover): the event title, when it starts, and a green
///     Join button (or Open when there's no video link)
///
/// Same fixed-canvas architecture as `BluetoothIslandView`.
struct CalendarIslandView: View {

    @ObservedObject var activity: CalendarActivity
    let isExpanded: Bool

    private typealias Compact = DesignTokens.StatusPillMetrics
    private typealias Expanded = DesignTokens.CalendarMetrics

    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visibleSize: CGSize {
        isExpanded ? activity.expandedSize : activity.compactSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - visibleSize.width) / 2
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: isExpanded
                    ? DesignTokens.Shape.expandedTopRadius
                    : DesignTokens.Shape.compactTopRadius,
                bottomRadius: isExpanded
                    ? DesignTokens.Shape.expandedBottomRadius
                    : DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: visibleSize.width, height: visibleSize.height)
            .position(x: canvasSize.width / 2, y: visibleSize.height / 2)

            Group {
                if isExpanded {
                    expandedPanel
                } else {
                    compactRow
                }
            }
            .frame(width: visibleSize.width, height: visibleSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(
            width: canvasSize.width,
            height: canvasSize.height,
            alignment: .topLeading
        )
        .animation(
            AnimationTokens.shapeMorph(isExpanding: isExpanded),
            value: isExpanded
        )
        .animation(AnimationTokens.stateUpdate, value: activity.stage)
    }

    // MARK: - Countdown text

    /// "5 min" / "1 min" / "Now" — recomputed every second so it stays
    /// true while the pill is up.
    private func countdown(at date: Date) -> String {

        guard let start = activity.event?.start else { return "" }

        let remaining = start.timeIntervalSince(date)

        if remaining <= 30 { return "Now" }

        return "\(Int((remaining / 60).rounded(.up))) min"
    }

    private func subtitle(at date: Date) -> String {

        guard let start = activity.event?.start else { return "" }

        let time = start.formatted(date: .omitted, time: .shortened)
        let remaining = start.timeIntervalSince(date)

        if remaining <= 30 { return "Starting now · \(time)" }

        return "Starts in \(Int((remaining / 60).rounded(.up))) min · \(time)"
    }

    // MARK: - Compact

    private var compactRow: some View {

        HStack(spacing: 0) {

            Image(systemName: "calendar")
                .font(.system(size: Compact.glyphSize, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.calendarAccent)
                .frame(width: Compact.iconSlot, height: Compact.iconSlot)

            Spacer(minLength: 0)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(countdown(at: context.date))
                    .font(Compact.labelFont)
                    .monospacedDigit()
                    .foregroundStyle(DesignTokens.Color.calendarAccent)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.horizontal, Compact.edgePadding)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout — nothing renders here.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            HStack(spacing: Expanded.iconToTextGap) {

                DeviceIconView(
                    symbolName: "calendar",
                    diameter: Expanded.iconSize
                )

                VStack(alignment: .leading, spacing: 2) {

                    Text(activity.event?.title ?? "Event")
                        .font(DesignTokens.Typography.title)
                        .tracking(DesignTokens.Typography.letterSpacingTight)
                        .foregroundStyle(DesignTokens.Color.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(subtitle(at: context.date))
                            .font(Expanded.subtitleFont)
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                actionButton
            }
            .padding(.horizontal, Expanded.edgePadding)
            .frame(maxHeight: .infinity)
            .padding(.bottom, Expanded.bottomPadding)
        }
    }

    @ViewBuilder
    private var actionButton: some View {

        if activity.event?.joinURL != nil {

            Button {
                activity.join()
            } label: {
                Text("Join")
                    .font(Expanded.buttonFont)
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, Expanded.buttonHorizontalPadding)
                    .frame(height: Expanded.buttonHeight)
                    .background(Capsule().fill(DesignTokens.Color.joinAccent))
            }
            .buttonStyle(CalendarPressStyle())

        } else {

            Button {
                activity.openCalendar()
            } label: {
                Text("Open")
                    .font(Expanded.buttonFont)
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .padding(.horizontal, Expanded.buttonHorizontalPadding)
                    .frame(height: Expanded.buttonHeight)
                    .background(Capsule().fill(DesignTokens.Color.deviceIconBackground))
            }
            .buttonStyle(CalendarPressStyle())
        }
    }
}

/// Same press feedback as the Bluetooth Disconnect button.
private struct CalendarPressStyle: ButtonStyle {

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
