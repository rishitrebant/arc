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

    // MARK: - Development Paths

    private var adapterScriptPath: String {

        guard let path =
            Bundle.main.path(
                forResource: "mediaremote-adapter",
                ofType: "pl"
            )
        else {
            fatalError(
                "mediaremote-adapter.pl was not found in the app bundle."
            )
        }

        return path
    }

    private var frameworkPath: String {

        guard let path =
            Bundle.main.path(
                forResource: "MediaRemoteAdapter",
                ofType: "framework"
            )
        else {
            fatalError(
                "MediaRemoteAdapter.framework was not found in the app bundle."
            )
        }

        return path
    }
    // MARK: - Live Playback Tracking

    private var currentState:
        MusicPlaybackState?

    /// Position reported by the adapter at the last sync.
    private var baseElapsed:
        TimeInterval = 0

    /// Wall-clock moment corresponding to `baseElapsed`.
    private var baseTimestamp:
        Date = .now

    /// Playback speed reported by the adapter.
    private var playbackRate:
        Double = 0

    /// Drives the visible progress locally between adapter updates.
    private var progressTimer:
        Timer?

    // MARK: - Start

    func start() {

        guard !isRunning else {
            return
        }

        isRunning = true

        startAdapter()

        // Local progress ticker.
        //
        // This does NOT query MediaRemote.
        // It simply advances the already-known position smoothly.
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

        isRunning = false

        progressTimer?.invalidate()
        progressTimer = nil

        process?.terminate()
        process = nil

        outputPipe = nil

        currentState = nil

        baseElapsed = 0
        baseTimestamp = .now
        playbackRate = 0

        stateSubject.send(nil)
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

        let process =
            Process()

        process.executableURL =
            URL(
                fileURLWithPath:
                    "/usr/bin/perl"
            )

        process.arguments = [
            adapterScriptPath,
            frameworkPath,
            "stream",
            "--no-diff"
        ]

        let pipe =
            Pipe()

        process.standardOutput =
            pipe

        process.standardError =
            FileHandle.nullDevice

        self.process =
            process

        self.outputPipe =
            pipe

        do {

            try process.run()

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

            self.process = nil
            self.outputPipe = nil

            return
        }

        readAdapterOutput(
            from:
                pipe
        )
    }

    // MARK: - Read Stream

    private func readAdapterOutput(
        from pipe:
            Pipe
    ) {

        DispatchQueue(
            label:
                "com.island.mediaremote.adapter.reader",
            qos:
                .userInitiated
        )
        .async { [weak self] in

            guard let self else {
                return
            }

            let handle =
                pipe.fileHandleForReading

            var buffer =
                Data()

            while self.isRunning {

                let chunk =
                    handle.availableData

                guard !chunk.isEmpty else {
                    break
                }

                buffer.append(
                    chunk
                )

                while let newlineRange =
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

                    DispatchQueue.main.async { [weak self] in

                        self?.handleAdapterLine(
                            cleanLine
                        )
                    }
                }
            }
        }
    }

    // MARK: - Parse Adapter Line

    private func handleAdapterLine(
        _ line:
            String
    ) {
        print("📦 ADAPTER:", line)

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
                message.type == "data"
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
        print("🎯 BUNDLE ID:", payload.bundleIdentifier ?? "NIL")

        // -------------------------------------------------------------
        // No active media.
        // -------------------------------------------------------------

        guard
            let title =
                payload.title,
            !title.isEmpty
        else {

            currentState = nil

            baseElapsed = 0
            playbackRate = 0

            stateSubject.send(nil)

            return
        }

        // -------------------------------------------------------------
        // Supported app.
        // -------------------------------------------------------------

        guard
            let bundleIdentifier =
                payload.bundleIdentifier,

            let app =
                MusicApp(
                    bundleIdentifier:
                        bundleIdentifier
                )
        else {

            return
        }

        // -------------------------------------------------------------
        // Duration.
        // -------------------------------------------------------------

        let duration =
            max(
                payload.duration ?? 0,
                0
            )

        // -------------------------------------------------------------
        // Playback rate.
        // -------------------------------------------------------------

        let rate =
            payload.playbackRate ?? 0

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

        // -------------------------------------------------------------
        // Adapter's latest known elapsed position.
        // -------------------------------------------------------------

        let reportedElapsed =
            max(
                payload.elapsedTimeNow
                    ?? payload.elapsedTime
                    ?? 0,
                0
            )

        // -------------------------------------------------------------
        // Sync local progress to the newest adapter position.
        //
        // Whenever MediaRemote gives us a new position, this resets
        // our local clock. Between updates, advanceProgress() takes
        // over so the visible time does not sit frozen.
        // -------------------------------------------------------------

        baseElapsed =
            reportedElapsed

        baseTimestamp =
            .now

        playbackRate =
            rate

        // -------------------------------------------------------------
        // Clamp.
        // -------------------------------------------------------------

        let safeElapsed =
            clampElapsed(
                reportedElapsed,
                duration:
                    duration
            )

        // -------------------------------------------------------------
        // Artwork.
        //
        // This remains exactly the same working adapter path.
        // -------------------------------------------------------------

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

        // -------------------------------------------------------------
        // Build state.
        // -------------------------------------------------------------

        let state =
            MusicPlaybackState(

                app:
                    app,

                title:
                    title,

                artist:
                    payload.artist ?? "",

                artwork:
                    artwork,

                isPlaying:
                    isPlaying,

                elapsed:
                    safeElapsed,

                duration:
                    duration
            )

        currentState =
            state

        stateSubject.send(
            state
        )

        print(
            "🎵 \(title)"
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

        // Time since the adapter last gave us a position.
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

        stateSubject.send(
            state

        )

        // If we reach the end locally, don't let the timer
        // continue pushing past the duration.
        if
            state.duration > 0,
            finalElapsed >= state.duration
        {

            state.isPlaying =
                false

            currentState =
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

        guard duration > 0 else {
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

    private func sendCommand(
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
                "❌ Failed to send command:"
            )

            print(
                error
            )
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
