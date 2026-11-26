import SwiftUI
import Combine
import EventKit
import AppKit

/// "Your next meeting is about to start."
///
/// Transient, like the charging and Bluetooth moments: shortly before an
/// event (the lead time in Settings) the island takes the notch with a
/// countdown, and again when the event actually starts. Hovering expands
/// it to the title, time and a Join button when the event has a video
/// link (Zoom, Meet, Teams, Webex, FaceTime).
///
/// Detection → State → Activity → Rendering, same shape as every other
/// activity. Events come from EventKit; this class only decides when to
/// be visible.
@MainActor
final class CalendarActivity: ObservableObject {

    static let kind: ActivityKind = .calendar

    struct Upcoming: Equatable {
        let id: String
        let title: String
        let start: Date
        let location: String?
        let joinURL: URL?
    }

    /// `countdown`: the quiet pill that counts down the last hour.
    /// `upcoming`: "starts in N min" alert. `now`: starting right now.
    enum Stage: Equatable {
        case countdown
        case upcoming
        case now
    }

    /// The countdown pill appears this long before an event.
    private static let countdownWindow: TimeInterval = 60 * 60

    /// Set by `AppDelegate`: lets the quiet countdown sit below a running
    /// timer while the alerts keep the calendar's usual, higher rank.
    var requestLowRank: (Bool) -> Void = { _ in }

    /// An alert (not the countdown) is on screen.
    private var isAlerting = false

    /// Events the user already acted on (Join / Open) — no more countdown.
    private var dismissedIDs: Set<String> = []

    @Published private(set) var isActive: Bool = false
    @Published private(set) var event: Upcoming?
    @Published private(set) var stage: Stage = .upcoming

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the pill never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1
    private static let pollInterval: TimeInterval = 20

    private let store = EKEventStore()
    private var hasAccess = false
    private var poller: Timer?
    private var hideWorkItem: DispatchWorkItem?

    /// "eventID|stage|start" keys already shown, so each moment pops up
    /// once however often we poll.
    private var alerted: Set<String> = []

    init() {

        Task { [weak self] in
            await self?.requestAccessAndStart()
        }
    }

    deinit {
        poller?.invalidate()
    }

    // MARK: - Access

    private func requestAccessAndStart() async {

        do {
            hasAccess = try await store.requestFullAccessToEvents()
        } catch {
            hasAccess = false
        }

        guard hasAccess else { return }

        let timer = Timer(
            timeInterval: Self.pollInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }

        RunLoop.main.add(timer, forMode: .common)
        poller = timer

        poll()
    }

    // MARK: - Detection → State

    private func poll() {

        guard hasAccess, AppSettings.showCalendarAlerts else {
            stopCountdown()
            return
        }

        let now = Date()
        let lead = TimeInterval(AppSettings.calendarLeadMinutes * 60)

        // From a minute ago (to catch "starting now") to the last hour.
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(Self.countdownWindow + 60),
            calendars: nil
        )

        let candidates = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }

        for ekEvent in candidates {

            let remaining = ekEvent.startDate.timeIntervalSince(now)
            let id = ekEvent.eventIdentifier ?? ekEvent.title ?? "event"

            if dismissedIDs.contains(id) { continue }

            let startKey = Int(ekEvent.startDate.timeIntervalSince1970)

            let nextStage: Stage

            if remaining <= 0, remaining > -60 {
                nextStage = .now
            } else if remaining > 0, remaining <= lead {
                nextStage = .upcoming
            } else if remaining > lead, remaining <= Self.countdownWindow {
                nextStage = .countdown
            } else {
                continue
            }

            let upcoming = Upcoming(
                id: id,
                title: ekEvent.title ?? "Event",
                start: ekEvent.startDate,
                location: ekEvent.location,
                joinURL: Self.joinURL(for: ekEvent)
            )

            if nextStage == .countdown {
                if !isAlerting { startCountdown(upcoming) }
                return
            }

            let key = "\(id)|\(nextStage)|\(startKey)"

            if alerted.contains(key) {
                // The alert already ran; until the event starts, keep
                // counting down quietly.
                if !isAlerting, remaining > 0 { startCountdown(upcoming) }
                return
            }

            alerted.insert(key)

            show(upcoming, stage: nextStage)

            return
        }

        if !isAlerting { stopCountdown() }
    }

    // MARK: - Countdown

    private func startCountdown(_ upcoming: Upcoming) {

        guard !isAlerting else { return }

        requestLowRank(true)

        if event != upcoming { event = upcoming }

        if stage != .countdown { stage = .countdown }

        hideWorkItem?.cancel()
        hideWorkItem = nil

        setActive(true)
    }

    private func stopCountdown() {

        guard !isAlerting, isActive else { return }

        requestLowRank(false)
        setActive(false)
    }

    private func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains {
            $0.isCurrentUser && $0.participantStatus == .declined
        } ?? false
    }

    /// First video-call link found in the event's URL, location or notes.
    private static func joinURL(for event: EKEvent) -> URL? {

        let hosts = [
            "zoom.us", "meet.google.com", "teams.microsoft.com",
            "teams.live.com", "webex.com", "facetime.apple.com"
        ]

        var haystacks: [String] = []
        if let url = event.url?.absoluteString { haystacks.append(url) }
        if let location = event.location { haystacks.append(location) }
        if let notes = event.notes { haystacks.append(notes) }

        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else {
            return nil
        }

        for text in haystacks {

            let range = NSRange(text.startIndex..., in: text)

            for match in detector.matches(in: text, range: range) {

                guard
                    let url = match.url,
                    let host = url.host?.lowercased(),
                    hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
                else {
                    continue
                }

                return url
            }
        }

        return nil
    }

    // MARK: - Visibility

    private func show(_ upcoming: Upcoming, stage: Stage) {

        // The alert takes the calendar's usual, higher rank.
        requestLowRank(false)

        isAlerting = true

        event = upcoming
        self.stage = stage

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.calendarDisplayDuration)
    }

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

        isAlerting = false

        // Back to the quiet countdown if the event hasn't started yet.
        if let start = event?.start, start.timeIntervalSinceNow > 0 {
            poll()
            return
        }

        requestLowRank(false)
        setActive(false)
    }

    private func scheduleHideCheck(after delay: TimeInterval) {

        hideWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            if self.isIslandCurrentlyHovered() {
                self.scheduleHideCheck(after: Self.hoverRecheckInterval)
            } else {
                self.hide()
            }
        }

        hideWorkItem = work

        DispatchQueue.main.asyncAfter(
            deadline: .now() + delay,
            execute: work
        )
    }

    private func setActive(_ shouldBeActive: Bool) {

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Actions

    func join() {

        if let url = event?.joinURL {
            NSWorkspace.shared.open(url)
        }

        if let id = event?.id { dismissedIDs.insert(id) }

        hide()
    }

    func openCalendar() {

        if let app = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.iCal"
        ) {
            NSWorkspace.shared.openApplication(
                at: app,
                configuration: NSWorkspace.OpenConfiguration()
            )
        }

        if let id = event?.id { dismissedIDs.insert(id) }

        hide()
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {

        // Only an alert gives way; the countdown just waits its turn.
        if isAlerting { hide() }
    }

    // MARK: - Sizing

    /// The colour the island's shadow glows while this is showing.
    var shadowAccent: Color? {
        DesignTokens.Color.calendarAccent
    }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.CalendarMetrics.expandedWidth,
            height: DesignTokens.CalendarMetrics.expandedHeight
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        CalendarIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension CalendarActivity: Activity {}

// MARK: - Shared pill

extension CalendarActivity: MinimalPresentable {

    private func shortCountdown() -> String {

        guard let start = event?.start else { return "" }

        let remaining = start.timeIntervalSinceNow

        return remaining <= 30 ? "Now" : "\(Int((remaining / 60).rounded(.up)))m"
    }

    func minimalView() -> AnyView {
        AnyView(
            MinimalBubble {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DesignTokens.Color.calendarAccent)
            }
        )
    }

    var earWidth: CGFloat {
        Ear.edge + Ear.slot + Ear.gap + 30 + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(
            TimelineView(.periodic(from: .now, by: 1)) { [self] _ in
                HStack(spacing: Ear.gap) {
                    Image(systemName: "calendar")
                        .font(.system(size: 13, weight: .semibold))
                    Text(shortCountdown())
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundStyle(DesignTokens.Color.calendarAccent)
                .padding(.horizontal, Ear.edge)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity,
                    alignment: side == .leading ? .leading : .trailing
                )
            }
        )
    }
}
