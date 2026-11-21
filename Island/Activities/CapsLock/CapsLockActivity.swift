import SwiftUI
import Combine
import AppKit

/// "Caps Lock was just turned on / off."
///
/// Transient, like the charging and Bluetooth moments: takes the island
/// when the state flips, stays for
/// `AnimationTokens.capsLockDisplayDuration`, then hands it back.
///
/// Detection polls `CGEventSource.flagsState`, which reports the
/// system-wide modifier state without any privacy permission (a global
/// key-event monitor would need Accessibility access).
@MainActor
final class CapsLockActivity: ObservableObject {

    static let kind: ActivityKind = .capsLock

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isCapsLockOn: Bool = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private static let pollInterval: TimeInterval = 0.15

    private var poller: Timer?
    private var hideWorkItem: DispatchWorkItem?

    init() {

        // Baseline first — launching with Caps Lock already on isn't a
        // toggle and must not pop the island.
        isCapsLockOn = Self.currentState()

        let timer = Timer(
            timeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }

        RunLoop.main.add(timer, forMode: .common)
        poller = timer
    }

    deinit {
        poller?.invalidate()
    }

    private static func currentState() -> Bool {
        CGEventSource
            .flagsState(.combinedSessionState)
            .contains(.maskAlphaShift)
    }

    // MARK: - Detection → State

    private func poll() {

        let now = Self.currentState()

        guard now != isCapsLockOn else { return }

        isCapsLockOn = now

        guard AppSettings.showCapsLockIndicator else { return }

        setActive(true)

        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AnimationTokens.capsLockDisplayDuration,
            execute: work
        )
    }

    private func hide() {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        setActive(false)
    }

    private func setActive(_ shouldBeActive: Bool) {

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

    /// Reuses AirDrop's measured pill (icon left, status right).
    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.AirDropMetrics.compactWidth,
            height: DesignTokens.AirDropMetrics.compactHeight
        )
    }

    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        CapsLockIslandView(activity: self)
    }
}

extension CapsLockActivity: Activity {}
