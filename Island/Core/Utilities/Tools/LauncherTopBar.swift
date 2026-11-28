import SwiftUI

/// The strip along the top of the launcher's home page, either side of the
/// notch: the system volume on the left; on the right, how long until the
/// next water reminder and today's active time.
struct LauncherTopBar: View {

    @ObservedObject var activity: LauncherActivity

    @StateObject private var volume = SystemVolumeControl()
    @ObservedObject private var bluetooth: BluetoothActivity

    @AppStorage(AppSettings.Key.showBatteryRings)
    private var showBatteryRings = AppSettings.Default.showBatteryRings

    init(activity: LauncherActivity) {
        self.activity = activity
        self._bluetooth = ObservedObject(wrappedValue: activity.bluetooth)
    }

    /// Devices first, this Mac last (so it sits in the far corner).
    private var orderedRings: [LauncherActivity.BatteryItem] {
        let items = activity.batteryItems
        return Array(items.filter { $0.address != nil }.prefix(3)) + items.filter { $0.address == nil }
    }

    var body: some View {

        HStack(spacing: 0) {

            // Left of the notch: the volume, and — right beside the notch —
            // the water ring.
            HStack(spacing: 10) {

                if volume.isAvailable {
                    VolumeSlider(volume: volume)
                }

                Spacer(minLength: 0)

                if let water = activity.water {
                    WaterCountdown(water: water)
                }
            }
            .frame(width: 112)

            Spacer(minLength: DesignTokens.FileDropMetrics.notchWidth)

            // Right of the notch: the connected devices, and this Mac last,
            // at the far corner.
            HStack(spacing: 9) {

                Spacer(minLength: 0)

                if showBatteryRings {
                    ForEach(orderedRings) { item in
                        BatteryDot(item: item)
                    }
                }
            }
            .frame(width: 112)
        }
        .padding(.horizontal, DesignTokens.LauncherMetrics.edgePadding)
        .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)
        .onAppear { volume.refresh() }
    }
}

/// A speaker and a thin level bar you can drag.
private struct VolumeSlider: View {

    @ObservedObject var volume: SystemVolumeControl

    private let width: CGFloat = 36

    private var symbol: String {
        if volume.level <= 0.001 { return "speaker.slash.fill" }
        if volume.level < 0.34 { return "speaker.wave.1.fill" }
        if volume.level < 0.67 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    var body: some View {

        HStack(spacing: 8) {

            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .frame(width: 16)
                .contentTransition(.symbolEffect(.replace))

            ZStack(alignment: .leading) {

                Capsule().fill(Color.white.opacity(0.18))

                Capsule()
                    .fill(Color.white.opacity(0.85))
                    .frame(width: max(4, width * volume.level))
            }
            .frame(width: width, height: 4)
            .frame(height: 22)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        volume.set(value.location.x / width)
                    }
            )
            .accessibilityLabel("Volume")
            .accessibilityValue("\(Int(volume.level * 100)) percent")
        }
        .animation(.easeOut(duration: 0.1), value: volume.level)
    }
}

/// A ring that empties as the next water reminder gets closer. Absent
/// while the reminder is off.
private struct WaterCountdown: View {

    @ObservedObject var water: WaterActivity

    var body: some View {

        if let next = water.nextReminder {

            TimelineView(.periodic(from: .now, by: 15)) { context in

                let remaining = max(0, next.timeIntervalSince(context.date))
                let fraction = min(1, remaining / WaterActivity.interval)

                // Just a ring: full right after a reminder, emptying until
                // the next one.
                ZStack {

                    Circle()
                        .stroke(WaterActivity.accent.opacity(0.25), lineWidth: 2.4)

                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(WaterActivity.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "drop.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(WaterActivity.accent)
                }
                .frame(width: 20, height: 20)
                .help("Next water reminder")
            }
        }
    }
}


/// One device (or this Mac) as a small ring: its icon inside, its charge
/// around it. Red at 20% or less. Hover for the name and number.
private struct BatteryDot: View {

    let item: LauncherActivity.BatteryItem

    private var tint: Color {
        item.percent <= 20 ? DesignTokens.Color.lowBatteryAccent : DesignTokens.Color.chargingAccent
    }

    var body: some View {

        ZStack {

            Circle()
                .stroke(Color.white.opacity(0.16), lineWidth: 2.4)

            Circle()
                .trim(from: 0, to: max(0.02, min(1, Double(item.percent) / 100)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: item.symbolName)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(DesignTokens.Color.primaryText)
        }
        .frame(width: 22, height: 22)
        .help("\(item.name) — \(item.percent)%")
        .accessibilityLabel("\(item.name), \(item.percent) percent")
    }
}
