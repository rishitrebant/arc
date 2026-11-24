import Foundation
import AppKit
import Combine

/// Reads a video playing in a browser from the system's Now Playing
/// stream, and controls it.
///
/// It runs its own MediaRemote adapter stream (the same bundled helper
/// the Music module uses) and keeps only media whose source is a browser.
/// Play/pause is the standard MediaRemote toggle; ±5 seconds is a seek to
/// the computed position, which YouTube's media session supports.
///
/// Whether a browser video is actually on YouTube is checked by looking
/// through the browser's tabs for one with that title on a youtube.com
/// address. That needs the user's Automation permission for that
/// browser; without it the answer is "unknown" and the caller decides.
@MainActor
final class MediaRemoteYouTubeService {

    // MARK: - Output

    private let stateSubject = CurrentValueSubject<WebVideoState?, Never>(nil)

    var statePublisher: AnyPublisher<WebVideoState?, Never> {
        stateSubject.eraseToAnyPublisher()
    }

    // MARK: - Adapter

    private var process: Process?
    private var isRunning = false

    /// Set by `start()`, cleared by `stop()` — so an adapter that dies on
    /// its own is restarted, but one we stopped is not.
    private var shouldRun = false

    private var adapterScriptPath: String {
        Bundle.main.path(forResource: "mediaremote-adapter", ofType: "pl") ?? ""
    }

    private var frameworkPath: String {
        Bundle.main.path(forResource: "MediaRemoteAdapter", ofType: "framework") ?? ""
    }

    // MARK: - Local progress

    private var current: WebVideoState?
    private var baseElapsed: TimeInterval = 0
    private var baseTimestamp = Date()
    private var progressTimer: Timer?

    /// Cached YouTube check, keyed by "title|channel", so a track is
    /// only looked up once.
    private var youtubeCache: [String: Bool?] = [:]
    private var pendingKey: String?

    /// Anything shorter is a notification chime, not a video.
    private static let minimumDuration: TimeInterval = 5

    // MARK: - Lifecycle

    func start() {

        shouldRun = true

        guard !isRunning else { return }

        guard
            FileManager.default.fileExists(atPath: adapterScriptPath),
            FileManager.default.fileExists(atPath: frameworkPath)
        else {
            debugLog("YouTube: adapter not found in the app bundle.")
            return
        }

        isRunning = true

        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        newProcess.arguments = [adapterScriptPath, frameworkPath, "stream", "--no-diff"]

        let pipe = Pipe()
        newProcess.standardOutput = pipe
        newProcess.standardError = FileHandle.nullDevice

        // If the adapter exits on its own the stream goes quiet and the
        // island would never hear about the video again — start it over.
        newProcess.terminationHandler = { [weak self] finished in

            Task { @MainActor in

                guard
                    let self,
                    self.shouldRun,
                    self.process === finished
                else {
                    return
                }

                debugLog("YouTube: adapter exited, restarting.")

                self.progressTimer?.invalidate()
                self.progressTimer = nil
                self.process = nil
                self.isRunning = false

                try? await Task.sleep(nanoseconds: 2_000_000_000)

                if self.shouldRun { self.start() }
            }
        }

        do {
            try newProcess.run()
        } catch {
            debugLog("YouTube: failed to start adapter:", error)
            isRunning = false
            return
        }

        process = newProcess

        read(from: pipe)

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.advanceProgress() }
        }

        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    func stop() {

        shouldRun = false
        isRunning = false

        progressTimer?.invalidate()
        progressTimer = nil

        process?.terminate()
        process = nil

        current = nil
        stateSubject.send(nil)
    }

    // MARK: - Reading

    private func read(from pipe: Pipe) {

        DispatchQueue(label: "com.island.youtube.reader", qos: .userInitiated).async {
            [weak self] in

            let handle = pipe.fileHandleForReading
            var buffer = Data()

            while true {

                let chunk = handle.availableData
                guard !chunk.isEmpty else { break }

                buffer.append(chunk)

                while let newline = buffer.range(of: Data([0x0A])) {

                    let lineData = buffer.subdata(in: 0..<newline.lowerBound)
                    buffer.removeSubrange(0...newline.lowerBound)

                    guard !lineData.isEmpty else { continue }

                    DispatchQueue.main.async {
                        self?.handle(line: lineData)
                    }
                }
            }
        }
    }

    private struct Message: Decodable {
        let type: String?
        let payload: Payload?
    }

    private struct Payload: Decodable {
        let bundleIdentifier: String?
        let parentApplicationBundleIdentifier: String?
        let playing: Bool?
        let title: String?
        let artist: String?
        let duration: TimeInterval?
        let elapsedTime: TimeInterval?
        let elapsedTimeNow: TimeInterval?
        let playbackRate: Double?
        let artworkData: String?
    }

    private func handle(line: Data) {

        guard
            isRunning,
            let message = try? JSONDecoder().decode(Message.self, from: line),
            message.type == "data"
        else {
            return
        }

        guard let payload = message.payload else { return }

        // Not a browser (or nothing playing): there's no video.
        guard
            let browser = WebBrowser.resolve(
                bundleID: payload.bundleIdentifier,
                parentBundleID: payload.parentApplicationBundleIdentifier
            ),
            let title = payload.title, !title.isEmpty
        else {
            clear()
            return
        }

        // A live stream's duration is infinite, and the adapter can't
        // print infinity — it logs an error and sends the update with the
        // duration LEFT OUT. So "no duration" from a browser means live;
        // a duration that IS present but tiny is a notification chime.
        // A live stream can also report a zero duration on a later update,
        // which must not be mistaken for a chime and drop the video.
        let isLive = payload.duration == nil || payload.duration == 0
        let duration = max(payload.duration ?? 0, 0)

        guard isLive || duration >= Self.minimumDuration else {
            clear()
            return
        }

        // An update that doesn't say whether it's playing keeps the last
        // known answer — a live stream isn't re-announced, so guessing
        // "paused" would hide it for good after the linger time.
        let isPlaying = payload.playing
            ?? payload.playbackRate.map { $0 > 0.01 }
            ?? current?.isPlaying
            ?? false

        let reportedElapsed = max(payload.elapsedTimeNow ?? payload.elapsedTime ?? 0, 0)

        let elapsed = isLive ? 0 : min(reportedElapsed, duration)

        var thumbnail: NSImage?

        if
            let base64 = payload.artworkData,
            let data = Data(base64Encoded: base64)
        {
            thumbnail = NSImage(data: data)
        }

        let channel = payload.artist ?? ""
        let key = "\(title)|\(channel)"

        baseElapsed = elapsed
        baseTimestamp = Date()

        var state = WebVideoState(
            title: title,
            channel: channel,
            thumbnail: thumbnail,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            isLive: isLive,
            isYouTube: youtubeCache[key] ?? nil,
            browser: browser
        )

        // A video we haven't checked yet: look it up once, and publish
        // nothing until the answer is in. (Publishing first would flash
        // the wrong logo, or briefly show a video that isn't YouTube.)
        // Progress keeps ticking underneath in the meantime.
        if !youtubeCache.keys.contains(key) {

            current = state

            if pendingKey != key {

                pendingKey = key

                let wanted = browser

                Task { [weak self] in

                    let result = await BrowserTabInspector.isYouTube(
                        browser: wanted,
                        videoTitle: title
                    )

                    guard let self else { return }

                    self.youtubeCache[key] = .some(result)
                    self.pendingKey = nil

                    if var latest = self.current, latest.title == title {
                        latest.isYouTube = result
                        self.current = latest
                        self.stateSubject.send(latest)
                    }
                }
            }

            return
        }

        state.isYouTube = youtubeCache[key] ?? nil

        current = state
        stateSubject.send(state)
    }

    private func clear() {

        guard current != nil else { return }

        current = nil
        pendingKey = nil
        stateSubject.send(nil)
    }

    // MARK: - Progress

    private func advanceProgress() {

        // A live stream has no timeline to advance.
        guard isRunning, var state = current, state.isPlaying, !state.isLive else { return }

        let elapsed = baseElapsed + max(Date().timeIntervalSince(baseTimestamp), 0)

        state.elapsed = min(elapsed, state.duration)

        current = state
        stateSubject.send(state)
    }

    // MARK: - Controls

    func togglePlayPause() {
        runAdapter(["send", "2"])
    }

    /// Jumps by `seconds` (negative to go back), clamped to the video.
    func skip(by seconds: TimeInterval) {

        // Nothing to seek in on a live stream — and seeking to
        // "elapsed + 5" with elapsed 0 would jump to its very start.
        guard let state = current, !state.isLive else { return }

        let target = min(max(state.elapsed + seconds, 0), state.duration)

        baseElapsed = target
        baseTimestamp = Date()

        var updated = state
        updated.elapsed = target
        current = updated
        stateSubject.send(updated)

        runAdapter(["seek", "\(Int(target * 1_000_000))"])
    }

    /// Rewinds a LIVE stream. There's no timeline position to seek from
    /// (the stream's length is infinite and elapsed time reads 0), so this
    /// asks the player itself to go back — MediaRemote's "Rewind 15
    /// Seconds" (command 12), the one relative skip the adapter accepts.
    func rewindLive() {
        runAdapter(["send", "12"])
    }

    private func runAdapter(_ arguments: [String]) {

        guard
            FileManager.default.fileExists(atPath: adapterScriptPath),
            FileManager.default.fileExists(atPath: frameworkPath)
        else {
            return
        }

        let command = Process()
        command.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        command.arguments = [adapterScriptPath, frameworkPath] + arguments
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice

        try? command.run()
    }
}

// MARK: - Is this tab YouTube?

/// Looks through a browser's tabs for the one playing a video and reports
/// whether it's on YouTube.
enum BrowserTabInspector {

    /// `true` / `false` when the browser's tabs could be read, `nil` when
    /// they couldn't (Firefox, Automation access denied, browser quit).
    static func isYouTube(browser: WebBrowser, videoTitle: String) async -> Bool? {

        guard let name = browser.scriptName else { return nil }

        guard
            NSWorkspace.shared.runningApplications.contains(where: {
                browser.bundleIDs.contains($0.bundleIdentifier ?? "")
            })
        else {
            return nil
        }

        let titleProperty = browser.isSafari ? "name" : "title"

        // Never launches the browser: it's running, or we returned above.
        let script = """
        tell application "\(name)"
            set out to ""
            repeat with w in windows
                repeat with t in tabs of w
                    set out to out & (\(titleProperty) of t) & "||" & (URL of t) & linefeed
                end repeat
            end repeat
            return out
        end tell
        """

        guard let output = await run(script) else { return nil }

        let wanted = videoTitle.lowercased()

        for line in output.split(separator: "\n") {

            let parts = line.components(separatedBy: "||")

            guard parts.count >= 2 else { continue }

            let tabTitle = parts[0].lowercased()
            let url = parts[1].lowercased()

            let onYouTube = url.contains("youtube.com") || url.contains("youtu.be")

            if onYouTube, tabTitle.contains(wanted) || wanted.contains(tabTitle) {
                return true
            }
        }

        // The tabs were readable and none of them is this video on YouTube.
        return false
    }

    private static func run(_ script: String) async -> String? {

        await withCheckedContinuation { continuation in

            DispatchQueue.global(qos: .userInitiated).async {

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: String(data: data, encoding: .utf8))
            }
        }
    }
}
