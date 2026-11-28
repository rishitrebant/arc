import SwiftUI
import Combine
import AppKit

/// "Up next": as a song is about to end, a small card shows what plays
/// after it, with a button to skip straight to it. Off in Settings.
///
/// The next song comes from Apple Music's current playlist (a script
/// asks it). Spotify exposes no queue to other apps, and a shuffled
/// playlist has no known "next", so the card simply doesn't appear there.
@MainActor
final class NextUpActivity: ObservableObject {

    static let kind: ActivityKind = .nextUp

    @Published private(set) var isActive = false
    @Published private(set) var title = ""
    @Published private(set) var artist = ""
    @Published private(set) var artwork: NSImage?

    private let isActiveSubject = CurrentValueSubject<Bool, Never>(false)

    var isActivePublisher: AnyPublisher<Bool, Never> {
        isActiveSubject.eraseToAnyPublisher()
    }

    /// Set by `AppDelegate` — the card never goes away under the cursor.
    var isIslandCurrentlyHovered: () -> Bool = { false }

    private let music: MusicActivity
    private var cancellable: AnyCancellable?

    /// How close to the end the card appears, and how long it stays.
    private static let leadTime: TimeInterval = 14
    private static let displayDuration: TimeInterval = 8

    private var shownForTrack = ""
    private var hideWork: DispatchWorkItem?
    private var isFetching = false

    init(music: MusicActivity) {

        self.music = music

        cancellable = music.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.handle(state)
            }
    }

    private func handle(_ state: MusicPlaybackState?) {

        guard let state, state.isPlaying else {
            hide()
            return
        }

        let key = "\(state.title)|\(state.artist)|\(Int(state.duration))"

        // A new song: the card for the last one is stale.
        if key != shownForTrack, isActive { hide() }

        guard
            AppSettings.nextUpEnabled,
            state.app == .appleMusic,
            state.duration > 40,
            key != shownForTrack,
            !isFetching
        else {
            return
        }

        let remaining = state.duration - state.elapsed

        guard remaining <= Self.leadTime, remaining > 2 else { return }

        isFetching = true

        Task { [weak self] in

            let next = await Self.fetchNextTrack()

            guard let self else { return }

            self.isFetching = false
            self.shownForTrack = key

            guard let next, AppSettings.nextUpEnabled else { return }

            self.title = next.title
            self.artist = next.artist
            self.artwork = next.artwork

            self.present()
        }
    }

    // MARK: - Showing

    private func present() {

        isActive = true
        isActiveSubject.send(true)

        scheduleHide(after: Self.displayDuration)
    }

    private func scheduleHide(after delay: TimeInterval) {

        hideWork?.cancel()

        let work = DispatchWorkItem { [weak self] in

            guard let self else { return }

            if self.isIslandCurrentlyHovered() {
                self.scheduleHide(after: 1)
            } else {
                self.hide()
            }
        }

        hideWork = work

        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func hide() {

        hideWork?.cancel()
        hideWork = nil

        guard isActive else { return }

        isActive = false
        isActiveSubject.send(false)
    }

    func skipToNext() {
        music.skipForward()
        hide()
    }

    // MARK: - Asking Music

    private static func fetchNextTrack() async -> (title: String, artist: String, artwork: NSImage?)? {

        let artPath = NSTemporaryDirectory() + "arc-nextup-art"

        try? FileManager.default.removeItem(atPath: artPath)

        // Name and artist, and — when the track has artwork — its picture,
        // written to a temporary file for us to read back.
        let script = """
        tell application "Music"
            if shuffle enabled then return ""
            set i to index of current track
            set pl to current playlist
            if i < (count of tracks of pl) then
                set t to track (i + 1) of pl
                try
                    set d to raw data of artwork 1 of t
                    set f to open for access (POSIX file "\(artPath)") with write permission
                    set eof f to 0
                    write d to f
                    close access f
                end try
                return (name of t) & "||" & (artist of t)
            end if
            return ""
        end tell
        """

        return await withCheckedContinuation { continuation in

            DispatchQueue.global(qos: .userInitiated).async {

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice

                do { try process.run() } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard
                    process.terminationStatus == 0,
                    let text = String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                    !text.isEmpty
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let parts = text.components(separatedBy: "||")

                let artwork = NSImage(contentsOfFile: artPath)

                continuation.resume(returning: (parts[0], parts.count > 1 ? parts[1] : "", artwork))
            }
        }
    }

    // MARK: - Activity

    func didBecomeActive() {}

    func didResignActive() { hide() }

    var shadowAccent: Color? { nil }

    var compactSize: CGSize { CGSize(width: 340, height: 96) }

    var expandedSize: CGSize { compactSize }

    @ViewBuilder
    func islandView(isExpanded: Bool) -> some View {
        NextUpIslandView(activity: self)
    }
}

extension NextUpActivity: Activity {}

private struct NextUpIslandView: View {

    @ObservedObject var activity: NextUpActivity

    var body: some View {

        ZStack(alignment: .top) {

            IslandShape(
                topRadius: DesignTokens.Shape.expandedTopRadius,
                bottomRadius: DesignTokens.Shape.expandedBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)

            VStack(spacing: 0) {

                // Clear of the notch (29pt) so nothing sits behind it.
                Color.clear.frame(height: DesignTokens.Shape.collapsedNotchHeight + 2)

                HStack(spacing: 12) {

                    Group {
                        if let artwork = activity.artwork {
                            Image(nsImage: artwork)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "music.note")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(DesignTokens.Color.secondaryText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(DesignTokens.Color.deviceIconBackground)
                        }
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 1) {

                        Text("Up next")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DesignTokens.Color.secondaryText)

                        Text(activity.title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignTokens.Color.primaryText)
                            .lineLimit(1)

                        if !activity.artist.isEmpty {
                            Text(activity.artist)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DesignTokens.Color.secondaryText)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button {
                        activity.skipToNext()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.Color.primaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(DesignTokens.Color.controlDisc))
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityLabel("Skip to next song")
                }
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity)
            }
            .frame(width: activity.compactSize.width, height: activity.compactSize.height)
        }
        .frame(width: DesignTokens.sharedCanvasSize.width, height: DesignTokens.sharedCanvasSize.height, alignment: .top)
    }
}
