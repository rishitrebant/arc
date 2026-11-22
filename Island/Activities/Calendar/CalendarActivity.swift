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

    /// "Starts in N min" vs "starting right now".
    enum Stage: Equatable {
        case upcoming
        case now
    }

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

        guard hasAccess, AppSettings.showCalendarAlerts else { return }

        let now = Date()
        let lead = TimeInterval(AppSettings.calendarLeadMinutes * 60)

        // From a minute ago (to catch "starting now") to the lead time.
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(lead + 60),
            calendars: nil
        )

        let candidates = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }

        for ekEvent in candidates {

            let remaining = ekEvent.startDate.timeIntervalSince(now)
            let id = ekEvent.eventIdentifier ?? ekEvent.title ?? "event"
            let startKey = Int(ekEvent.startDate.timeIntervalSince1970)

            let nextStage: Stage

            if remaining <= 0, remaining > -60 {
                nextStage = .now
            } else if remaining > 0, remaining <= lead {
                nextStage = .upcoming
            } else {
                continue
            }

            let key = "\(id)|\(nextStage)|\(startKey)"

            guard !alerted.contains(key) else { continue }

            alerted.insert(key)

            show(Upcoming(
                id: id,
                title: ekEvent.title ?? "Event",
                start: ekEvent.startDate,
                location: ekEvent.location,
                joinURL: Self.joinURL(for: ekEvent)
            ), stage: nextStage)

            return
        }
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

        event = upcoming
        self.stage = stage

        setActive(true)
        scheduleHideCheck(after: AnimationTokens.calendarDisplayDuration)
    }

    private func hide() {

        hideWorkItem?.cancel()
        hideWorkItem = nil

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

        hide()
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {
        hide()
    }

    // MARK: - Sizing

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
