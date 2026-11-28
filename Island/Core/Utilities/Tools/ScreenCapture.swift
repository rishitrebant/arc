import Foundation
import AppKit
import Vision

/// Region capture and "copy text from screen".
///
/// The picture is taken by macOS's own `screencapture` (the crosshair you
/// know) and read by Vision on this Mac — it works on anything drawn on
/// screen, selectable or not: images, videos, PDFs, apps that don't let
/// you select text. The first use asks for Screen Recording permission.
enum ScreenCapture {

    /// Lets you drag out a region. Returns false if you cancelled (Esc).
    private static func selectRegion(arguments: [String]) async -> Bool {

        await withCheckedContinuation { continuation in

            DispatchQueue.global(qos: .userInitiated).async {

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = arguments

                do { try process.run() } catch {
                    continuation.resume(returning: false)
                    return
                }

                process.waitUntilExit()

                continuation.resume(returning: process.terminationStatus == 0)
            }
        }
    }

    /// A screenshot of the region you drag, straight to the clipboard.
    @discardableResult
    static func copyScreenshot() async -> Bool {
        await selectRegion(arguments: ["-i", "-x", "-c"])
    }

    /// Drag a region; its text (and any QR code) is copied. Returns what
    /// was copied, or nil when you cancelled or nothing was found.
    static func copyTextFromScreen() async -> String? {

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("arc-ocr-\(UUID().uuidString).png")

        defer { try? FileManager.default.removeItem(at: url) }

        guard await selectRegion(arguments: ["-i", "-x", url.path]),
              FileManager.default.fileExists(atPath: url.path)
        else {
            return nil
        }

        return await Task.detached(priority: .userInitiated) { () -> String? in

            let text = VNRecognizeTextRequest()
            text.recognitionLevel = .accurate
            text.automaticallyDetectsLanguage = true

            let codes = VNDetectBarcodesRequest()

            let handler = VNImageRequestHandler(url: url, options: [:])

            guard (try? handler.perform([text, codes])) != nil else { return nil }

            var lines: [String] = []

            // Top to bottom, as read.
            let observations = (text.results ?? []).sorted {
                $0.boundingBox.midY > $1.boundingBox.midY
            }

            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    lines.append(candidate.string)
                }
            }

            for code in codes.results ?? [] {
                if let payload = code.payloadStringValue, !lines.contains(payload) {
                    lines.append(payload)
                }
            }

            let result = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)

            return result.isEmpty ? nil : result

        }.value
    }
}
