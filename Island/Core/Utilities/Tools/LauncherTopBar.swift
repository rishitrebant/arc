import SwiftUI

/// The strip along the top of the launcher's home page, either side of the
/// notch: the system volume on the left; on the right, how long until the
/// next water reminder and today's active time.
struct LauncherTopBar: View {

    @ObservedObject var activity: LauncherActivity

    @StateObject private var volume = SystemVolumeControl()
    @ObservedObject private var screenTime = ScreenTimeTracker.shared

    @AppStorage(AppSettings.Key.showScreenTime)
    private var showScreenTime = AppSettings.Default.showScreenTime

    var body: some View {

        HStack(spacing: 0) {

            if volume.isAvailable {
                VolumeSlider(volume: volume)
                    .frame(width: 104, alignment: .leading)
            } else {
                Color.clear.frame(width: 104)
            }

            Spacer(minLength: DesignTokens.FileDropMetrics.notchWidth)

            HStack(spacing: 10) {

                if let water = activity.water {
                    WaterCountdown(water: water)
                }

                if showScreenTime {
                    HStack(spacing: 4) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 10, weight: .medium))
                        Text(ScreenTimeTracker.format(screenTime.todaySeconds))
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                    }
                    .foregroundStyle(DesignTokens.Color.secondaryText)
                    .help("Active at this Mac today")
                }
            }
            .frame(width: 104, alignment: .trailing)
        }
        .padding(.horizontal, DesignTokens.LauncherMetrics.edgePadding)
        .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)
        .onAppear { volume.refresh() }
    }
}

/// A speaker and a thin level bar you can drag.
private struct VolumeSlider: View {

    @ObservedObject var volume: SystemVolumeControl

    private let width: CGFloat = 62

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

/// A ring that empties as the next water reminder gets closer, with the
/// minutes left beside it. Absent while the reminder is off.
private struct WaterCountdown: View {

    @ObservedObject var water: WaterActivity

    var body: some View {

        if let next = water.nextReminder {

            TimelineView(.periodic(from: .now, by: 15)) { context in

                let remaining = max(0, next.timeIntervalSince(context.date))
                let fraction = min(1, remaining / WaterActivity.interval)
                let minutes = Int((remaining / 60).rounded(.up))

                HStack(spacing: 5) {

                    ZStack {

                        Circle()
                            .stroke(WaterActivity.accent.opacity(0.25), lineWidth: 2.2)

                        Circle()
                            .trim(from: 0, to: max(0.02, fraction))
                            .stroke(WaterActivity.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                            .rotationEffect(.degrees(-90))

                        Image(systemName: "drop.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(WaterActivity.accent)
                    }
                    .frame(width: 18, height: 18)

                    Text("\(minutes)m")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.Color.secondaryText)
                }
                .help("Next water reminder")
            }
        }
    }
}
