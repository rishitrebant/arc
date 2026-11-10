import Foundation
import IOKit.ps

/// Watches the Mac's internal battery / power adapter state.
///
/// Uses IOKit's power-source notifications (the same ones the system
/// battery menu uses), so changes arrive the instant the charger is
/// plugged in or pulled out — no polling.
///
/// This type only reports facts about power. It knows nothing about the
/// island, priorities, or rendering; `ChargingActivity` decides what
/// those facts mean.
@MainActor
final class PowerSourceMonitor {

    struct Snapshot: Equatable {

        /// False on desktop Macs (no internal battery) — the activity
        /// simply never shows there.
        var hasBattery: Bool

        /// True while a power adapter is connected, whether or not the
        /// battery is actively taking charge (e.g. optimized charging
        /// holding at 80%).
        var isPluggedIn: Bool

        /// 0...100
        var percent: Int

        /// Battery is full and the adapter is connected.
        var isFullyCharged: Bool

        static let noBattery = Snapshot(
            hasBattery: false,
            isPluggedIn: false,
            percent: 0,
            isFullyCharged: false
        )
    }

    /// Fires on the main run loop whenever anything about the power
    /// source changes (adapter connected/removed, percentage ticks).
    var onChange: ((Snapshot) -> Void)?

    private var runLoopSource: CFRunLoopSource?

    // MARK: - Lifecycle

    func start() {

        guard runLoopSource == nil else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()

        // `powerSourceChanged` is a plain C-compatible function (see the
        // bottom of this file) — it can't capture anything, so `self`
        // travels through `context`.
        guard let source = IOPSNotificationCreateRunLoopSource(
            powerSourceChanged,
            context
        )?.takeRetainedValue() else {
            return
        }

        // `.commonModes` so updates still arrive while a menu is being
        // tracked or the run loop is in another mode.
        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )

        runLoopSource = source
    }

    func stop() {

        guard let source = runLoopSource else { return }

        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            source,
            .commonModes
        )

        runLoopSource = nil
    }

    // MARK: - Reading

    func currentSnapshot() -> Snapshot {

        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?
                .takeRetainedValue() as? [CFTypeRef]
        else {
            return .noBattery
        }

        for source in sources {

            guard
                let description = IOPSGetPowerSourceDescription(
                    info,
                    source
                )?.takeUnretainedValue() as? [String: Any],

                (description[kIOPSTypeKey] as? String)
                    == kIOPSInternalBatteryType
            else {
                continue
            }

            let state =
                description[kIOPSPowerSourceStateKey] as? String

            let current =
                description[kIOPSCurrentCapacityKey] as? Int ?? 0

            let maximum =
                description[kIOPSMaxCapacityKey] as? Int ?? 100

            let isCharged =
                description[kIOPSIsChargedKey] as? Bool ?? false

            let percent =
                maximum > 0
                    ? Int((Double(current) / Double(maximum) * 100).rounded())
                    : 0

            let isPluggedIn = (state == kIOPSACPowerValue)

            return Snapshot(
                hasBattery: true,
                isPluggedIn: isPluggedIn,
                percent: min(max(percent, 0), 100),
                isFullyCharged: isPluggedIn && (isCharged || percent >= 100)
            )
        }

        return .noBattery
    }
}

// MARK: - C callback

/// Top-level on purpose: an `IOPowerSourceCallbackType` is a C function
/// pointer, so it can't be a closure that captures state or inherits
/// actor isolation. IOKit delivers it on the main run loop (the source is
/// added to `CFRunLoopGetMain()` above), which is what makes
/// `assumeIsolated` valid here.
private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {

    guard let context else { return }

    let monitor = Unmanaged<PowerSourceMonitor>
        .fromOpaque(context)
        .takeUnretainedValue()

    MainActor.assumeIsolated {
        monitor.onChange?(monitor.currentSnapshot())
    }
}
