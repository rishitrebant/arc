import Foundation
import AppKit
import Combine

final class MediaRemoteMusicService:
    NSObject,
    MusicService {

    // MARK: - Publisher

    private let stateSubject =
        CurrentValueSubject<
            MusicPlaybackState?,
            Never
        >(nil)

    var playbackStatePublisher:
        AnyPublisher<
            MusicPlaybackState?,
            Never
        > {

        stateSubject
            .eraseToAnyPublisher()
    }

    // MARK: - Adapter Process

    private var process:
        Process?

    private var outputPipe:
        Pipe?

    private var isRunning =
        false

    // MARK: - Paths

    private var adapterScriptPath:
        String {

        guard let path =
            Bundle.main.path(
                forResource:
                    "mediaremote-adapter",

                ofType:
                    "pl"
            )
        else {

            fatalError(
                "mediaremote-adapter.pl was not found in the app bundle."
            )
        }

        return path
    }

    private var frameworkPath:
        String {

        guard let path =
            Bundle.main.path(
                forResource:
                    "MediaRemoteAdapter",

                ofType:
                    "framework"
            )
        else {

            fatalError(
                "MediaRemoteAdapter.framework was not found in the app bundle."
            )
        }

        return path
    }

    // MARK: - Playback State

    /// Current supported music state shown by the island.
    private var currentState:
        MusicPlaybackState?

    /// Last supported Apple Music / Spotify state.
    ///
    /// IMPORTANT:
    /// This survives while YouTube/Safari temporarily takes over
    /// Now Playing, so playback commands still know which music app
    /// they belong to.
    private var lastSupportedState:
        MusicPlaybackState?

    /// What MediaRemote currently reports as Now Playing.
    private var currentNowPlayingBundleIdentifier:
        String?

    /// Whether a real competing media source is currently hiding
    /// the music island.
    private var isCompetingMedia =
        false

    /// Last reported position.
    private var baseElapsed:
        TimeInterval = 0

    /// Time at which baseElapsed was received.
    private var baseTimestamp:
        Date = .now

    /// Playback rate.
    private var playbackRate:
        Double = 0

    /// Smooth local progress timer.
    private var progressTimer:
        Timer?

    // MARK: - Unsupported Media

    /// Anything shorter than this is treated as a transient sound
    /// rather than meaningful media.
    ///
    /// Example:
    /// WhatsApp notification = ~2 sec → ignored.
    /// YouTube video = several minutes → hides island.
    private let unsupportedMediaMinimumDuration:
        TimeInterval = 10

    // MARK: - Start

    func start() {

        guard
            !isRunning
        else {
            return
        }

        isRunning =
            true

        startAdapter()

        progressTimer =
            Timer.scheduledTimer(
                withTimeInterval:
                    0.1,

                repeats:
                    true
            ) { [weak self] _ in

                self?.advanceProgress()
            }
    }

    // MARK: - Stop

    func stop() {

        isRunning =
            false

        progressTimer?.invalidate()

        progressTimer =
            nil

        process?.terminate()

        process =
            nil

        outputPipe =
            nil

        currentState =
            nil

        lastSupportedState =
            nil

        currentNowPlayingBundleIdentifier =
            nil

        isCompetingMedia =
            false

        baseElapsed =
            0

        baseTimestamp =
            .now

        playbackRate =
            0

        stateSubject.send(
            nil
        )
    }

    deinit {

        stop()
    }

    // MARK: - Start Adapter

    private func startAdapter() {

        guard
            FileManager.default.fileExists(
                atPath:
                    adapterScriptPath
            )
        else {

            print(
                "❌ Adapter script not found:"
            )

            print(
                adapterScriptPath
            )

            return
        }

        guard
            FileManager.default.fileExists(
                atPath:
                    frameworkPath
            )
        else {

            print(
                "❌ Adapter framework not found:"
            )

            print(
                frameworkPath
            )

            return
        }

        let newProcess =
            Process()

        newProcess.executableURL =
            URL(
                fileURLWithPath:
                    "/usr/bin/perl"
            )

        newProcess.arguments = [

            adapterScriptPath,

            frameworkPath,

            "stream",

            "--no-diff"
        ]

        let pipe =
            Pipe()

        newProcess.standardOutput =
            pipe

        newProcess.standardError =
            FileHandle.nullDevice

        process =
            newProcess

        outputPipe =
            pipe

        do {

            try newProcess.run()

            print(
                "✅ MediaRemote Adapter started"
            )

        } catch {

            print(
                "❌ Failed to start MediaRemote Adapter:"
            )

            print(
                error
            )

            process =
                nil

            outputPipe =
                nil

            return
        }

        readAdapterOutput(
            from:
                pipe
        )
    }

    // MARK: - Read Adapter Output

    private func readAdapterOutput(
        from pipe:
            Pipe
    ) {

        DispatchQueue(
            label:
                "com.island.mediaremote.reader",

            qos:
                .userInitiated
        )
        .async { [weak self] in

            guard
                let self
            else {
                return
            }

            let handle =
                pipe.fileHandleForReading

            var buffer =
                Data()

            while
                self.isRunning
            {

                let chunk =
                    handle.availableData

                guard
                    !chunk.isEmpty
                else {
                    break
                }

                buffer.append(
                    chunk
                )

                while
                    let newlineRange =
                        buffer.range(
                            of:
                                Data([0x0A])
                        )
                {

                    let lineData =
                        buffer.subdata(
                            in:
                                0..<newlineRange.lowerBound
                        )

                    buffer.removeSubrange(
                        0...newlineRange.lowerBound
                    )

                    guard
                        let line =
                            String(
                                data:
                                    lineData,

                                encoding:
                                    .utf8
                            )
                    else {
                        continue
                    }

                    let cleanLine =
                        line.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    guard
                        !cleanLine.isEmpty
                    else {
                        continue
                    }

                    DispatchQueue.main.async {
                        [weak self] in

                        self?.handleAdapterLine(
                            cleanLine
                        )
                    }
                }
            }
        }
    }

    // MARK: - Handle Adapter Line

    private func handleAdapterLine(
        _ line:
            String
    ) {

        print(
            "📦 ADAPTER:",
            line
        )

        guard
            let data =
                line.data(
                    using:
                        .utf8
                )
        else {
            return
        }

        do {

            let message =
                try JSONDecoder()
                    .decode(
                        AdapterMessage.self,
                        from:
                            data
                    )

            guard
                message.type ==
                    "data"
            else {
                return
            }

            guard
                let payload =
                    message.payload
            else {
                return
            }

            handlePayload(
                payload
            )

        } catch {

            print(
                "❌ Adapter JSON decode failed:"
            )

            print(
                error
            )

            print(
                "RAW:"
            )

            print(
                line
            )
        }
    }

    // MARK: - Handle Payload

    private func handlePayload(
        _ payload:
            AdapterPayload
    ) {

        let bundleIdentifier =
            payload.bundleIdentifier

        print(
            "🎯 BUNDLE ID:",
            bundleIdentifier ?? "NIL"
        )

        if let bundleIdentifier {

            currentNowPlayingBundleIdentifier =
                bundleIdentifier
        }

        // -------------------------------------------------------------
        // Unsupported source
        // -------------------------------------------------------------

        guard
            let bundleIdentifier,

            let app =
                MusicApp(
                    bundleIdentifier:
                        bundleIdentifier
                )
        else {

            print(
                "ℹ️ Unsupported Now Playing source:"
                + " \(bundleIdentifier ?? "unknown")"
            )

            handleUnsupportedMedia(
                payload
            )

            return
        }

        // -------------------------------------------------------------
        // Supported music source is back.
        //
        // This immediately ends the competing-media state and updates
        // the saved music state.
        // -------------------------------------------------------------

        isCompetingMedia =
            false

        handleSupportedMusic(
            payload,
            app:
                app
        )
    }

    // MARK: - Unsupported Media

    private func handleUnsupportedMedia(
        _ payload:
            AdapterPayload
    ) {

        let duration =
            max(
                payload.duration ?? 0,
                0
            )

        let rate =
            payload.playbackRate ?? 0

        let isPlaying =
            payload.playing
            ?? (rate > 0.01)

        let isLongFormMedia =
            duration >=
                unsupportedMediaMinimumDuration

        // -------------------------------------------------------------
        // REAL COMPETING MEDIA
        //
        // Example:
        // Safari / WebKit
        // YouTube
        // duration = 580 sec
        // playing = true
        //
        // Hide the island, BUT preserve the music state internally.
        // -------------------------------------------------------------

        if
            isPlaying,
            isLongFormMedia
        {

            guard
                !isCompetingMedia
            else {
                return
            }

            isCompetingMedia =
                true

            print(
                "🎬 Competing media detected."
            )

            print(
                "   Source:"
                + " \(payload.bundleIdentifier ?? "unknown")"
            )

            print(
                "   Title:"
                + " \(payload.title ?? "")"
            )

            print(
                "   Duration:"
                + " \(duration)s"
            )

            print(
                "🚫 Hiding music island."
            )

            // IMPORTANT:
            //
            // DO NOT erase lastSupportedState.
            //
            // The island can disappear while we still remember:
            //
            // Spotify → paused
            // or
            // Apple Music → playing
            //
            // This is what fixes the first-play problem.

            currentState =
                nil

            baseElapsed =
                0

            baseTimestamp =
                .now

            playbackRate =
                0

            stateSubject.send(
                nil
            )

            return
        }

        // -------------------------------------------------------------
        // COMPETING MEDIA STOPPED
        //
        // Restore the last known supported music state.
        //
        // This means the first click on Play/Pause after YouTube stops
        // already knows whether it should control Spotify or Music.
        // -------------------------------------------------------------

        if
            isCompetingMedia,
            !isPlaying
        {

            guard
                let savedState =
                    lastSupportedState
            else {

                isCompetingMedia =
                    false

                return
            }

            print(
                "↩️ Competing media stopped."
            )

            print(
                "🎵 Restoring:"
                + " \(savedState.app.rawValue)"
            )

            isCompetingMedia =
                false

            currentState =
                savedState

            baseElapsed =
                savedState.elapsed

            baseTimestamp =
                .now

            playbackRate =
                savedState.isPlaying
                    ? 1
                    : 0

            stateSubject.send(
                savedState
            )

            return
        }

        // -------------------------------------------------------------
        // SHORT SOUND / NOTIFICATION
        //
        // Do absolutely nothing.
        //
        // WhatsApp notification, notification chime, etc.
        // will therefore not kill the island.
        // -------------------------------------------------------------

        print(
            "🔔 Short/unimportant unsupported event."
        )

        print(
            "   Keeping current music state."
        )
    }

    // MARK: - Supported Music

    private func handleSupportedMusic(
        _ payload:
            AdapterPayload,

        app:
            MusicApp
    ) {

        let duration =
            max(
                payload.duration ?? 0,
                0
            )

        let rate =
            payload.playbackRate
            ?? 0

        let isPlaying:
            Bool

        if let playing =
            payload.playing {

            isPlaying =
                playing

        } else {

            isPlaying =
                rate > 0.01
        }

        let reportedElapsed =
            max(
                payload.elapsedTimeNow
                    ?? payload.elapsedTime
                    ?? 0,

                0
            )

        baseElapsed =
            reportedElapsed

        baseTimestamp =
            .now

        playbackRate =
            rate

        let safeElapsed =
            clampElapsed(
                reportedElapsed,

                duration:
                    duration
            )

        // MARK: Artwork

        var artwork:
            NSImage?

        if
            let artworkBase64 =
                payload.artworkData,

            let artworkData =
                Data(
                    base64Encoded:
                        artworkBase64
                )
        {

            artwork =
                NSImage(
                    data:
                        artworkData
                )
        }

        // MARK: Create state

        let state =
            MusicPlaybackState(

                app:
                    app,

                title:
                    payload.title
                    ?? "",

                artist:
                    payload.artist
                    ?? "",

                artwork:
                    artwork,

                isPlaying:
                    isPlaying,

                elapsed:
                    safeElapsed,

                duration:
                    duration
            )

        // -------------------------------------------------------------
        // SAVE IT.
        //
        // This survives unsupported media taking over Now Playing.
        // -------------------------------------------------------------

        lastSupportedState =
            state

        currentState =
            state

        stateSubject.send(
            state
        )

        print(
            "🎵 \(state.title)"
            + " | \(app.rawValue)"
            + " | playing: \(isPlaying)"
            + " | elapsed: \(safeElapsed)"
            + " | duration: \(duration)"
        )
    }

    // MARK: - Local Progress

    private func advanceProgress() {

        guard
            isRunning,

            var state =
                currentState,

            state.isPlaying
        else {
            return
        }

        let delta =
            Date()
                .timeIntervalSince(
                    baseTimestamp
                )

        let newElapsed =
            baseElapsed
            + (
                max(
                    delta,
                    0
                )
                *
                max(
                    playbackRate,
                    0
                )
            )

        let finalElapsed =
            clampElapsed(
                newElapsed,

                duration:
                    state.duration
            )

        state.elapsed =
            finalElapsed

        currentState =
            state

        // Keep the saved state synchronized too.
        lastSupportedState =
            state

        stateSubject.send(
            state
        )

        if
            state.duration > 0,

            finalElapsed >=
                state.duration
        {

            state.isPlaying =
                false

            currentState =
                state

            lastSupportedState =
                state

            stateSubject.send(
                state
            )
        }
    }

    // MARK: - Clamp

    private func clampElapsed(
        _ value:
            TimeInterval,

        duration:
            TimeInterval
    ) -> TimeInterval {

        let safe =
            max(
                value,
                0
            )

        guard
            duration > 0
        else {
            return safe
        }

        return min(
            safe,
            duration
        )
    }

    // MARK: - Playback Commands

    func togglePlayPause() {

        sendCommand(
            2
        )
    }

    func skipForward() {

        sendCommand(
            4
        )
    }

    func skipBackward() {

        sendCommand(
            5
        )
    }

    // MARK: - Command Routing

    private func sendCommand(
        _ command:
            Int
    ) {

        // -------------------------------------------------------------
        // THIS IS THE IMPORTANT FIX.
        //
        // If competing media temporarily cleared currentState,
        // fall back to the last supported music state.
        // -------------------------------------------------------------

        guard
            let state =
                currentState
                ?? lastSupportedState
        else {

            print(
                "🚫 No supported music state available."
            )

            return
        }

        let targetApp =
            state.app

        let targetBundle =
            targetApp.bundleIdentifier

        if
            currentNowPlayingBundleIdentifier
                == targetBundle
        {

            print(
                "🎯 Sending MediaRemote command to:"
                + " \(targetBundle)"
            )

            sendMediaRemoteCommand(
                command
            )

            return
        }

        // -------------------------------------------------------------
        // Another app is currently Now Playing.
        //
        // Send directly to the remembered music app.
        // -------------------------------------------------------------

        print(
            "🔀 Current Now Playing:"
            + " \(currentNowPlayingBundleIdentifier ?? "unknown")"
            + " | Target music app:"
            + " \(targetBundle)"
        )

        sendDirectMusicAppCommand(
            command,
            app:
                targetApp
        )
    }

    // MARK: - MediaRemote Command

    private func sendMediaRemoteCommand(
        _ command:
            Int
    ) {

        let commandProcess =
            Process()

        commandProcess.executableURL =
            URL(
                fileURLWithPath:
                    "/usr/bin/perl"
            )

        commandProcess.arguments = [

            adapterScriptPath,

            frameworkPath,

            "send",

            "\(command)"
        ]

        commandProcess.standardOutput =
            FileHandle.nullDevice

        commandProcess.standardError =
            FileHandle.nullDevice

        do {

            try commandProcess.run()

        } catch {

            print(
                "❌ Failed to send MediaRemote command:"
            )

            print(
                error
            )
        }
    }

    // MARK: - Direct Music App Command

    private func sendDirectMusicAppCommand(
        _ command:
            Int,

        app:
            MusicApp
    ) {

        let script =
            appleScriptFor(
                command:
                    command,

                app:
                    app
            )

        guard
            !script.isEmpty
        else {

            print(
                "🚫 No direct command available."
            )

            return
        }

        DispatchQueue.main.async {

            var errorInfo:
                NSDictionary?

            guard
                let appleScript =
                    NSAppleScript(
                        source:
                            script
                    )
            else {

                print(
                    "❌ Could not create AppleScript."
                )

                return
            }

            let result =
                appleScript
                    .executeAndReturnError(
                        &errorInfo
                    )

            if let errorInfo {

                print(
                    "❌ AppleScript command failed:"
                )

                print(
                    errorInfo
                )

                if let number =
                    errorInfo[
                        NSAppleScript.errorNumber
                    ] as? NSNumber,

                    number.intValue ==
                        -1743
                {

                    print(
                        "⚠️ Automation permission required for:"
                        + " \(app.rawValue)"
                    )

                    print(
                        "Go to:"
                        + " System Settings → Privacy & Security"
                        + " → Automation"
                    )
                }

            } else {

                print(
                    "✅ Direct music command sent:"
                    + " \(app.rawValue)"
                    + " | command \(command)"
                )

                _ = result
            }
        }
    }

    // MARK: - AppleScript

    private func appleScriptFor(
        command:
            Int,

        app:
            MusicApp
    ) -> String {

        switch app {

        case .appleMusic:

            switch command {

            case 2:

                return """
                tell application "Music"
                    playpause
                end tell
                """

            case 4:

                return """
                tell application "Music"
                    next track
                end tell
                """

            case 5:

                return """
                tell application "Music"
                    previous track
                end tell
                """

            default:

                return ""
            }

        case .spotify:

            switch command {

            case 2:

                return """
                tell application "Spotify"
                    playpause
                end tell
                """

            case 4:

                return """
                tell application "Spotify"
                    next track
                end tell
                """

            case 5:

                return """
                tell application "Spotify"
                    previous track
                end tell
                """

            default:

                return ""
            }
        }
    }

    // MARK: - Models

    private struct AdapterMessage:
        Decodable {

        let type:
            String

        let diff:
            Bool?

        let payload:
            AdapterPayload?
    }

    private struct AdapterPayload:
        Decodable {

        let bundleIdentifier:
            String?

        let parentApplicationBundleIdentifier:
            String?

        let playing:
            Bool?

        let title:
            String?

        let artist:
            String?

        let album:
            String?

        let composer:
            String?

        let duration:
            TimeInterval?

        let elapsedTime:
            TimeInterval?

        let elapsedTimeNow:
            TimeInterval?

        let timestamp:
            String?

        let artworkMimeType:
            String?

        let artworkData:
            String?

        let playbackRate:
            Double?
    }
}
