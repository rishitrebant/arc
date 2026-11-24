import SwiftUI
import Combine

/// A video playing in the browser — YouTube controls in the notch, built
/// on the same template as Music: a compact pill (logo or thumbnail on
/// the left, waveform on the right) that expands on hover into the
/// thumbnail, title, channel, progress and ⟲5 · play/pause · 5⟳ controls.
///
/// Like Music it is on the island while the video plays, lingers for the
/// "Stay after pausing" time once paused, and never closes under the
/// cursor. Optional: switched off in Settings it never appears and the
/// video is left alone.
@MainActor
final class YouTubeActivity: ObservableObject {

    static let kind: ActivityKind = .youtube

    @Published private(set) var isActive: Bool = false
    @Published private(set) var video: WebVideoState?

    private let isActiveSubject =
        CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the island never closes under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private static let hoverRecheckInterval: TimeInterval = 1

    private let service: MediaRemoteYouTubeService
    private var cancellables: Set<AnyCancellable> = []
    private var settingsObserver: Task<Void, Never>?

    /// The latest report from the service, before Settings are applied.
    private var latest: WebVideoState?

    private var pauseTimer: DispatchWorkItem?

    /// The thumbnail's dominant colour — what the island's shadow glows.
    private var thumbnailAccent: Color = DesignTokens.Color.youtubeRed
    private var thumbnailAccentKey = ""

    var shadowAccent: Color? { thumbnailAccent }

    init(service providedService: MediaRemoteYouTubeService? = nil) {

        let service = providedService ?? MediaRemoteYouTubeService()

        self.service = service

        service.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state)
            }
            .store(in: &cancellables)

        // Follow the Settings toggles live.
        settingsObserver = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification
            ) {
                guard let self else { return }
                self.handle(self.latest)
            }
        }

        service.start()
    }

    deinit {
        settingsObserver?.cancel()
        let service = self.service
        Task { @MainActor in service.stop() }
    }

    // MARK: - State

    /// Whether this video is one the user wants controls for.
    private func isWanted(_ state: WebVideoState) -> Bool {

        guard AppSettings.youtubeControlsEnabled else { return false }

        switch AppSettings.youtubeDetection {

        case .anyVideo:
            return true

        case .youtubeOnly:
            // `nil` = couldn't be checked (Firefox, access denied): show
            // it rather than silently ignore a video the user is playing.
            return state.isYouTube != false
        }
    }

    private func handle(_ state: WebVideoState?) {

        latest = state

        guard let state, isWanted(state) else {
            video = nil
            pauseTimer?.cancel()
            pauseTimer = nil
            setActive(false)
            return
        }

        video = state

        // Recompute the glow colour only when the video changes — this
        // runs on every progress tick.
        let key = "\(state.title)|\(state.channel)|\(state.thumbnail != nil)"

        if key != thumbnailAccentKey {
            thumbnailAccentKey = key
            thumbnailAccent = ArtworkColorExtractor.dominantColor(
                from: state.thumbnail,
                fallback: DesignTokens.Color.youtubeRed
            )
        }

        if state.isPlaying {

            pauseTimer?.cancel()
            pauseTimer = nil

            if !isActive { setActive(true) }

        } else {

            if !isActive { return }

            if pauseTimer == nil {
                scheduleHideCheck(after: AppSettings.musicLingerDuration)
            }
        }
    }

    private func scheduleHideCheck(after delay: TimeInterval) {

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            if self.isIslandCurrentlyHovered() {
                self.scheduleHideCheck(after: Self.hoverRecheckInterval)
            } else {
                self.pauseTimer = nil
                self.setActive(false)
            }
        }

        pauseTimer = work

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

    // MARK: - Controls

    func togglePlayPause() {
        service.togglePlayPause()
    }

    func skipBack() {

        if video?.isLive == true {
            service.rewindLive()
        } else {
            service.skip(by: -Self.skipSeconds)
        }
    }

    func skipForward() {
        service.skip(by: Self.skipSeconds)
    }

    /// The amount ⟲ and ⟳ jump.
    static let skipSeconds: TimeInterval = 5

    // MARK: - Activity Lifecycle

    func didBecomeActive() {}

    func didResignActive() {}

    // MARK: - Sizing

    /// Music's width, but the same height as every other compact pill
    /// (Music's own pill is shorter; this one read as too small).
    var compactSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.compactWidth,
            height: DesignTokens.StatusPillMetrics.compactHeight
        )
    }

    var expandedSize: CGSize {
        CGSize(
            width: DesignTokens.MusicMetrics.expandedWidth,
            height: DesignTokens.MusicMetrics.expandedHeight
        )
    }

    // MARK: - Rendering

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {

        YouTubeIslandView(
            activity: self,
            isExpanded: isExpanded
        )
    }
}

extension YouTubeActivity: Activity {}

// MARK: - Shared pill

extension YouTubeActivity: MinimalPresentable {

    func minimalView() -> AnyView {
        AnyView(YouTubeMinimalBubble(activity: self))
    }

    var earWidth: CGFloat {
        Ear.edge + Ear.slot + Ear.gap + Ear.slot + Ear.edge
    }

    func earView(side: EarSide) -> AnyView {
        AnyView(YouTubeEar(activity: self, side: side))
    }
}

/// The YouTube pill's half of a shared pill: logo (or thumbnail) and
/// waveform — what its own compact pill shows.
private struct YouTubeEar: View {

    @ObservedObject var activity: YouTubeActivity
    let side: EarSide

    var body: some View {

        HStack(spacing: Ear.gap) {

            YouTubeCompactIconView(video: activity.video, size: Ear.slot)

            LiveWaveform(
                isPlaying: activity.video?.isPlaying ?? false,
                color: DesignTokens.Color.youtubeRed
            )
            .frame(width: Ear.slot, height: Ear.slot)
            .padding(.trailing, side == .trailing ? -Ear.glyphAir : 0)
        }
        .padding(.horizontal, Ear.edge)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: side == .leading ? .leading : .trailing
        )
    }
}

/// The detached bubble form (a charger pill is up, say).
private struct YouTubeMinimalBubble: View {

    @ObservedObject var activity: YouTubeActivity

    var body: some View {

        MinimalBubble {
            YouTubeCompactIconView(
                video: activity.video,
                size: DesignTokens.BubbleMetrics.contentSize
            )
            .opacity(activity.video?.isPlaying == true ? 1 : 0.55)
        }
    }
}
