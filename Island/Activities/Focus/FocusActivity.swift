import SwiftUI
import Combine
import Intents

/// "Focus turned on / off."
///
/// macOS tells an authorised app only whether the user is currently in a
/// Focus (`INFocusStatusCenter`) — not which one — so this shows a moon
/// and "On" / "Off". It needs the user's permission, asked for the first
/// time the feature is used, and is polled every couple of seconds
/// because the system offers no change notification outside an Intents
/// extension.
///
/// Transient, like the Caps Lock pill.
@MainActor
final class FocusActivity: ObservableObject {

    static let kind: ActivityKind = .focus

    @Published private(set) var isActive: Bool = false
    @Published private(set) var isFocused: Bool = false

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private static let pollInterval: TimeInterval = 2

    private var poller: Timer?
    private var hideWorkItem: DispatchWorkItem?
    private var lastKnown: Bool?

    init() {

        INFocusStatusCenter.default.requestAuthorization { _ in }

        let timer = Timer(
            timeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }

        RunLoop.main.add(timer, forMode: .common)
        poller = timer

        // Baseline — launching in a Focus isn't a change.
        lastKnown = Self.currentFocus()
        isFocused = lastKnown ?? false
    }

    deinit {
        poller?.invalidate()
    }

    /// `nil` until the user has authorised Island to read Focus status.
    private static func currentFocus() -> Bool? {

        guard
            INFocusStatusCenter.default.authorizationStatus == .authorized
        else {
            return nil
        }

        return INFocusStatusCenter.default.focusStatus.isFocused
    }

    // MARK: - Detection → State

    private var lastLoggedStatus: INFocusStatusAuthorizationStatus?

    private func poll() {

        let status = INFocusStatusCenter.default.authorizationStatus

        if status != lastLoggedStatus {
            lastLoggedStatus = status
            debugLog("🌙 Focus: authorization status", status.rawValue, "(0 undetermined, 1 restricted, 2 denied, 3 authorized)")
        }

        guard let now = Self.currentFocus() else { return }

        if now != lastKnown {
            debugLog("🌙 Focus: system reports focused =", now)
        }

        defer { lastKnown = now }

        // First authorised reading just sets the baseline.
        guard let previous = lastKnown, previous != now else { return }

        isFocused = now

        guard AppSettings.showFocusChanges else { return }

        setActive(true)

        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.hide()
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + AnimationTokens.focusDisplayDuration,
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

    /// The colour the island's shadow glows while this is showing.
    var shadowAccent: Color? {
        DesignTokens.Color.focusAccent
    }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize { compactSize }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        FocusIslandView(activity: self)
    }
}

extension FocusActivity: Activity {}
