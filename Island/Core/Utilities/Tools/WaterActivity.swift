import SwiftUI
import Combine

/// "Time for some water" — once an hour, switched on in Settings. It
/// appears as a small pill in the island and goes away by itself; there
/// is no notification, so no permission to give.
@MainActor
final class WaterActivity: ObservableObject {

    static let kind: ActivityKind = .water

    static let accent = Color(red: 0.35, green: 0.78, blue: 0.98)

    @Published private(set) var isActive = false

    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private static let interval: TimeInterval = 3600
    private static let displayDuration: TimeInterval = 7

    private var timer: Timer?
    private var hideWork: DispatchWorkItem?
    private var observer: Task<Void, Never>?

    init() {

        apply()

        observer = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            ) {
                self?.apply()
            }
        }
    }

    deinit {
        observer?.cancel()
        timer?.invalidate()
    }

    /// Starts or stops the hourly clock to match the Settings toggle.
    private func apply() {

        let enabled = UserDefaults.standard.bool(forKey: AppSettings.Key.waterReminderEnabled)

        if enabled, timer == nil {

            let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.remind() }
            }

            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer

        } else if !enabled, timer != nil {

            timer?.invalidate()
            timer = nil
            hide()
        }
    }

    private func remind() {

        guard !isActive else { return }

        isActive = true
        isActiveSubject.send(true)

        Haptics.open()

        hideWork?.cancel()

        let work = DispatchWorkItem { [weak self] in self?.hide() }

        hideWork = work

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration, execute: work)
    }

    func hide() {

        hideWork?.cancel()
        hideWork = nil

        guard isActive else { return }

        isActive = false
        isActiveSubject.send(false)
    }

    // MARK: - Activity

    func didBecomeActive() {}

    func didResignActive() { hide() }

    var shadowAccent: Color? { Self.accent }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.FileDropMetrics.notchWidth + 2 * 80,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize { compactSize }

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {
        WaterIslandView(activity: self)
    }
}

extension WaterActivity: Activity {}

private struct WaterIslandView: View {

    @ObservedObject var activity: WaterActivity

    var body: some View {

        ZStack(alignment: .top) {

            IslandShape(
                topRadius: DesignTokens.Shape.compactTopRadius,
                bottomRadius: DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)

            HStack(spacing: 0) {

                Image(systemName: "drop.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(WaterActivity.accent)
                    .symbolEffect(.pulse, options: .repeating)
                    .frame(width: 22)

                Spacer(minLength: 0)

                Text("Drink water")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WaterActivity.accent)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 14)
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)
        }
        .frame(width: DesignTokens.sharedCanvasSize.width, height: DesignTokens.sharedCanvasSize.height, alignment: .top)
    }
}
