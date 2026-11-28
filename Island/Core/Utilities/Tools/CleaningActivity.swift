import SwiftUI
import Combine
import AppKit
import ApplicationServices

/// Keyboard Cleaning Mode: every key press is swallowed so the keyboard
/// can be wiped down. The island shows the countdown, and a button to
/// unlock early; it unlocks by itself when time runs out.
///
/// Blocking keys needs the Accessibility permission (an event tap); the
/// first start asks for it.
@MainActor
final class CleaningActivity: ObservableObject {

    static let kind: ActivityKind = .cleaning

    @Published private(set) var isActive = false
    @Published private(set) var secondsLeft = 0

    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private static let duration: TimeInterval = 90

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var endDate: Date?
    private var timer: Timer?

    /// Locks the keyboard. Returns false (after asking macOS for the
    /// permission) when it isn't allowed to yet.
    @discardableResult
    func start() -> Bool {

        guard !isActive else { return true }

        guard AXIsProcessTrusted() else {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            return false
        }

        guard installTap() else { return false }

        endDate = Date().addingTimeInterval(Self.duration)
        secondsLeft = Int(Self.duration)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        isActive = true
        isActiveSubject.send(true)

        return true
    }

    func stop() {

        timer?.invalidate()
        timer = nil

        removeTap()

        guard isActive else { return }

        isActive = false
        isActiveSubject.send(false)
    }

    private func tick() {

        guard let endDate else { return }

        let remaining = endDate.timeIntervalSinceNow

        if remaining <= 0 {
            stop()
        } else {
            secondsLeft = Int(remaining.rounded(.up))
        }
    }

    // MARK: - Event tap

    private func installTap() -> Bool {

        var mask: CGEventMask = 0

        for type in [CGEventType.keyDown, .keyUp, .flagsChanged] {
            mask |= CGEventMask(1) << CGEventMask(type.rawValue)
        }

        // NSSystemDefined (14): the media and volume keys.
        mask |= CGEventMask(1) << 14

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, _ in

                // macOS switches a tap off if it's slow; leave that alone.
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    return Unmanaged.passUnretained(event)
                }

                // Swallow the key.
                return nil
            },
            userInfo: nil
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.source = source

        return true
    }

    private func removeTap() {

        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }

        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }

        tap = nil
        source = nil
    }

    // MARK: - Activity

    func didBecomeActive() {}

    func didResignActive() {}

    var shadowAccent: Color? { Color(red: 0.35, green: 0.78, blue: 0.98) }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth + 20,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(width: DesignTokens.CalendarMetrics.expandedWidth, height: 92)
    }

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {
        CleaningIslandView(activity: self, isExpanded: isExpanded)
    }
}

extension CleaningActivity: Activity {}

private struct CleaningIslandView: View {

    @ObservedObject var activity: CleaningActivity
    let isExpanded: Bool

    private let tint = Color(red: 0.35, green: 0.78, blue: 0.98)

    var body: some View {

        IslandMorphSurface(
            isExpanded: isExpanded,
            compactSize: activity.compactSize,
            expandedSize: activity.expandedSize
        ) {
            HStack(spacing: 0) {

                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 20)

                Spacer(minLength: 0)

                Text(format(activity.secondsLeft))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .contentTransition(.numericText(countsDown: true))
            }
            .padding(.horizontal, 12)
        } expanded: {
            VStack(spacing: 0) {

                Color.clear.frame(height: DesignTokens.DeviceCard.topInset)

                HStack(spacing: 14) {

                    Image(systemName: "keyboard")
                        .font(.system(size: 26, weight: .regular))
                        .foregroundStyle(tint)
                        .frame(width: 46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Keyboard locked")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(DesignTokens.Color.primaryText)
                        Text("Wipe it down — it unlocks in \(format(activity.secondsLeft))")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(DesignTokens.Color.secondaryText)
                    }

                    Spacer(minLength: 0)

                    Button {
                        activity.stop()
                    } label: {
                        Text("Unlock")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.black)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .background(Capsule().fill(tint))
                    }
                    .buttonStyle(PressableButtonStyle())
                }
                .padding(.horizontal, 22)
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func format(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
