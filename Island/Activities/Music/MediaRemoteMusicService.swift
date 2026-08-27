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

    // For now we are using the copy on your Desktop.
    // Later, when the backend is fully working, these will be changed
    // to Bundle.main paths for distribution.

    private let adapterScriptPath =
        "/Users/rishitrebant/Desktop/mediaremote-adapter/bin/mediaremote-adapter.pl"

    private let frameworkPath =
        "/Users/rishitrebant/Desktop/mediaremote-adapter/build/MediaRemoteAdapter.framework"

    // MARK: - Start

    func start() {

        guard !isRunning else {
            return
        }

        isRunning = true

        startAdapter()
    }

    // MARK: - Stop

    func stop() {

        isRunning = false

        process?.terminate()
        process = nil

        outputPipe = nil

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

        // `stream` gives us continuous updates.
        // `--no-diff` makes every payload contain the complete state.
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

    // MARK: - Read Adapter Output

    private func readAdapterOutput(
        from pipe:
            Pipe
    ) {

        let queue =
            DispatchQueue(
                label:
                    "com.island.mediaremote.adapter.reader",
                qos:
                    .userInitiated
            )

        queue.async { [weak self] in

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

            // Handle a final line without a trailing newline.
            if
                !buffer.isEmpty,
                let finalLine =
                    String(
                        data:
                            buffer,
                        encoding:
                            .utf8
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    ),
                !finalLine.isEmpty
            {

                DispatchQueue.main.async { [weak self] in

                    self?.handleAdapterLine(
                        finalLine
                    )
                }
            }
        }
    }

    // MARK: - Parse Adapter Line

    private func handleAdapterLine(
        _ line:
            String
    ) {

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

            handleMessage(
                message
            )

        } catch {

            print(
                "❌ Adapter JSON decode failed:"
            )

            print(
                error
            )

            print(
                "RAW LINE:"
            )

            print(
                line
            )
        }
    }

    // MARK: - Handle Message

    private func handleMessage(
        _ message:
            AdapterMessage
    ) {

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

        // -------------------------------------------------------------
        // No active media
        // -------------------------------------------------------------

        guard
            let title =
                payload.title,
            !title.isEmpty
        else {

            stateSubject.send(nil)

            return
        }

        // -------------------------------------------------------------
        // Supported application
        // -------------------------------------------------------------

        guard
            let bundleIdentifier =
                payload.bundleIdentifier,

            let musicApp =
                MusicApp(
                    bundleIdentifier:
                        bundleIdentifier
                )
        else {

            stateSubject.send(nil)

            return
        }

        // -------------------------------------------------------------
        // Duration
        // -------------------------------------------------------------

        let duration:
            TimeInterval =
                max(
                    payload.duration ?? 0,
                    0
                )

        // -------------------------------------------------------------
        // Elapsed
        //
        // Prefer elapsedTimeNow.
        // If it isn't supplied, use elapsedTime.
        // -------------------------------------------------------------

        let elapsed:
            TimeInterval =
                max(
                    payload.elapsedTimeNow
                        ?? payload.elapsedTime
                        ?? 0,
                    0
                )

        let safeElapsed:
            TimeInterval

        if duration > 0 {

            safeElapsed =
                min(
                    elapsed,
                    duration
                )

        } else {

            safeElapsed =
                elapsed
        }

        // -------------------------------------------------------------
        // Playing state
        // -------------------------------------------------------------

        let isPlaying:
            Bool

        if let playing =
            payload.playing {

            isPlaying =
                playing

        } else {

            let rate =
                payload.playbackRate ?? 0

            isPlaying =
                rate > 0.01
        }

        // -------------------------------------------------------------
        // Artwork
        //
        // The adapter already gives artworkData as base64.
        // Your terminal test proved this exists.
        // -------------------------------------------------------------

        var artwork:
            NSImage?

        if
            let artworkBase64 =
                payload.artworkData,

            !artworkBase64.isEmpty,

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
        // Debug
        // -------------------------------------------------------------

        print(
            "🎵 \(title)"
        )

        print(
            "Artist:",
            payload.artist ?? ""
        )

        print(
            "Playing:",
            isPlaying
        )

        print(
            "Elapsed:",
            safeElapsed
        )

        print(
            "Duration:",
            duration
        )

        print(
            "Artwork:",
            artwork != nil
        )

        // -------------------------------------------------------------
        // Publish
        // -------------------------------------------------------------

        stateSubject.send(

            MusicPlaybackState(

                app:
                    musicApp,

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

            print(
                "✅ Sent adapter command:",
                command
            )

        } catch {

            print(
                "❌ Failed to send adapter command:"
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

        let artworkMimeType:
            String?

        let artworkData:
            String?

        let playbackRate:
            Double?
    }
}
