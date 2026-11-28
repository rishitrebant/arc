import Foundation
import CoreGraphics

/// "Active today": the time you've actually been at the Mac, counted
/// while ARC runs (a stretch counts when you've touched the keyboard,
/// mouse or trackpad in the last couple of minutes).
///
/// macOS has no public Screen Time API for Mac apps, so this is ARC's own
/// count — kept on this Mac, a number per day, nothing more.
@MainActor
final class ScreenTimeTracker: ObservableObject {

    static let shared = ScreenTimeTracker()

    @Published private(set) var todaySeconds: Double = 0

    private static let tick: TimeInterval = 20
    private static let idleLimit: TimeInterval = 120

    private var timer: Timer?

    private static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "screenTime." + formatter.string(from: Date())
    }

    private init() {
        todaySeconds = UserDefaults.standard.double(forKey: Self.todayKey)
    }

    func start() {

        guard timer == nil else { return }

        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        timer.tolerance = 5

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func sample() {

        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: CGEventType(rawValue: ~0)!
        )

        // A new day starts a new count.
        let key = Self.todayKey

        if UserDefaults.standard.object(forKey: key) == nil {
            todaySeconds = 0
        }

        guard idle < Self.idleLimit else { return }

        todaySeconds += Self.tick

        UserDefaults.standard.set(todaySeconds, forKey: key)
    }

    /// "2h 14m", "38m", "<1m".
    static func format(_ seconds: Double) -> String {

        let minutes = Int(seconds / 60)

        if minutes < 1 { return "<1m" }

        return minutes >= 60
            ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
            : "\(minutes)m"
    }
}
