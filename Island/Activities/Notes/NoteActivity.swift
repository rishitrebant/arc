import SwiftUI
import Combine

/// A note pinned to the notch: a small pill with a note glyph while
/// nothing more important is up, the note itself when you hover it.
///
/// Notes are written and managed from the launcher (see
/// `LauncherIslandView`); this activity only shows the pinned one, and
/// is on the island exactly as long as one is pinned.
@MainActor
final class NoteActivity: ObservableObject {

    static let kind: ActivityKind = .note

    static let accent = Color(red: 255 / 255, green: 204 / 255, blue: 10 / 255)

    @Published private(set) var isActive: Bool = false

    let store: NoteStore

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    private var cancellable: AnyCancellable?

    init(store: NoteStore = .shared) {

        self.store = store

        cancellable = store.$notes
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.sync()
            }

        sync()
    }

    private func sync() {

        // The pinned note's text can change size; keep observers in step.
        objectWillChange.send()

        let shouldBeActive = store.pinned != nil

        guard shouldBeActive != isActive else { return }

        isActive = shouldBeActive
        isActiveSubject.send(shouldBeActive)
    }

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {}

    // MARK: - Sizing

    var shadowAccent: Color? { Self.accent }

    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.StatusPillMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    /// Tall enough for the note's own length (a line or two for most,
    /// at most six), under the notch.
    var expandedSize: CGSize {

        let length = store.pinned?.text.count ?? 0
        let lines = min(6, max(2, Int((Double(length) / 34).rounded(.up))))

        return CGSize(
            width: 340,
            height: DesignTokens.FileDropMetrics.notchKeepClearHeight + 30 + CGFloat(lines) * 19 + 20
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        NoteIslandView(activity: self, isExpanded: isExpanded)
    }
}

extension NoteActivity: Activity {}

// MARK: - Shared pill

extension NoteActivity: MinimalPresentable {

    func minimalView() -> AnyView {
        AnyView(
            MinimalBubble {
                Image(systemName: "note.text")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Self.accent)
            }
        )
    }

    var earWidth: CGFloat {
        Ear.edge + Ear.slot + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(
            Image(systemName: side == .leading ? "note.text" : "pin.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Self.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: side == .leading ? .trailing : .leading)
                .padding(.horizontal, Ear.edge)
        )
    }
}
