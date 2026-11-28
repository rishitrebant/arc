import Foundation
import AppKit
import AVFoundation
import PDFKit
import UniformTypeIdentifiers
import CoreText

/// A format a shelf file can be converted to.
enum ConversionTarget: String, CaseIterable, Identifiable {

    case jpeg, png, heic, pdf, mp4, m4a

    var id: String { rawValue }

    var title: String {
        switch self {
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .heic: return "HEIC"
        case .pdf: return "PDF"
        case .mp4: return "MP4 video"
        case .m4a: return "M4A audio"
        }
    }

    var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .heic: return "heic"
        case .pdf: return "pdf"
        case .mp4: return "mp4"
        case .m4a: return "m4a"
        }
    }

    var symbol: String {
        switch self {
        case .jpeg, .png, .heic: return "photo"
        case .pdf: return "doc.richtext"
        case .mp4: return "film"
        case .m4a: return "waveform"
        }
    }
}

/// What a file is, as far as conversion cares.
private enum FileKind {

    case image, pdf, text, video, audio, other

    init(url: URL) {

        let ext = url.pathExtension.lowercased()

        // Word-processor and web documents that macOS can open as text.
        if ["doc", "docx", "odt", "rtf", "rtfd", "html", "htm", "txt", "md", "markdown", "webarchive"].contains(ext) {
            self = .text
            return
        }

        guard let type = UTType(filenameExtension: ext) else {
            self = .other
            return
        }

        if type.conforms(to: .pdf) { self = .pdf }
        else if type.conforms(to: .image) { self = .image }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { self = .video }
        else if type.conforms(to: .audio) { self = .audio }
        else if type.conforms(to: .text) || type.conforms(to: .rtf) || type.conforms(to: .html) { self = .text }
        else { self = .other }
    }
}

/// Converts shelf files between common formats with the system's own
/// frameworks — nothing leaves the Mac. Results are new files; the
/// originals are untouched.
enum FileConverter {

    /// Targets that make sense for at least one of these files — and
    /// never the format a file already is.
    static func targets(for urls: [URL]) -> [ConversionTarget] {

        var found = Set<ConversionTarget>()

        for url in urls {

            let ext = url.pathExtension.lowercased()

            switch FileKind(url: url) {

            case .image:
                found.formUnion([.jpeg, .png, .heic, .pdf])

            case .pdf:
                found.formUnion([.png, .jpeg])

            case .text:
                found.insert(.pdf)

            case .video:
                found.formUnion([.mp4, .m4a])

            case .audio:
                found.insert(.m4a)

            case .other:
                break
            }

            // Already that format: nothing to do for this file alone.
            if let own = ConversionTarget.allCases.first(where: { $0.fileExtension == ext || (ext == "jpeg" && $0 == .jpeg) }),
               urls.count == 1 {
                found.remove(own)
            }
        }

        return ConversionTarget.allCases.filter(found.contains)
    }

    /// Converts every file that can become `target`; the rest are skipped.
    static func convert(_ urls: [URL], to target: ConversionTarget) async -> [URL] {

        var results: [URL] = []

        for url in urls {
            if let converted = await convert(url, to: target) {
                results.append(converted)
            }
        }

        return results
    }

    private static func convert(_ url: URL, to target: ConversionTarget) async -> URL? {

        let kind = FileKind(url: url)
        let output = outputURL(for: url, target: target)

        switch (kind, target) {

        case (.image, .jpeg), (.image, .png), (.image, .heic):
            return await detached { imageToImage(url, output, target) }

        case (.image, .pdf):
            return await detached { imageToPDF(url, output) }

        case (.pdf, .png), (.pdf, .jpeg):
            return await detached { pdfToImage(url, output, target) }

        case (.text, .pdf):
            return await detached { textToPDF(url, output) }

        case (.video, .mp4):
            return await export(url, output, preset: AVAssetExportPresetHighestQuality, type: .mp4)

        case (.video, .m4a), (.audio, .m4a):
            return await export(url, output, preset: AVAssetExportPresetAppleM4A, type: .m4a)

        default:
            return nil
        }
    }

    private static func detached(_ work: @escaping @Sendable () -> URL?) async -> URL? {
        await Task.detached(priority: .userInitiated, operation: work).value
    }

    private static func outputURL(for url: URL, target: ConversionTarget) -> URL {

        let base = url.deletingPathExtension().lastPathComponent
        // Shelf copies are prefixed with a UUID; keep the readable part.
        let readable = base.split(separator: "-", maxSplits: 5, omittingEmptySubsequences: false).count > 5
            ? base.split(separator: "-", maxSplits: 5, omittingEmptySubsequences: false).last.map(String.init) ?? base
            : base

        return ShelfFileStore.directory.appendingPathComponent(
            "\(UUID().uuidString)-\(readable).\(target.fileExtension)"
        )
    }

    // MARK: - Images

    private static func imageToImage(_ url: URL, _ output: URL, _ target: ConversionTarget) -> URL? {

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            return nil
        }

        let type: UTType = target == .png ? .png : target == .heic ? .heic : .jpeg

        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            return nil
        }

        // JPEG can't hold transparency: flatten onto white.
        let flattened = target == .jpeg ? flatten(image) ?? image : image

        CGImageDestinationAddImage(
            destination,
            flattened,
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        )

        return CGImageDestinationFinalize(destination) ? output : nil
    }

    private static func flatten(_ image: CGImage) -> CGImage? {

        guard let context = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)

        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)

        return context.makeImage()
    }

    private static func imageToPDF(_ url: URL, _ output: URL) -> URL? {

        guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else {
            return nil
        }

        let document = PDFDocument()
        document.insert(page, at: 0)

        return document.write(to: output) ? output : nil
    }

    // MARK: - PDF

    private static func pdfToImage(_ url: URL, _ output: URL, _ target: ConversionTarget) -> URL? {

        guard
            let document = PDFDocument(url: url),
            let page = document.page(at: 0)
        else {
            return nil
        }

        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2

        let image = page.thumbnail(
            of: CGSize(width: bounds.width * scale, height: bounds.height * scale),
            for: .mediaBox
        )

        guard
            let tiff = image.tiffRepresentation,
            let rep = NSBitmapImageRep(data: tiff),
            let data = rep.representation(
                using: target == .png ? .png : .jpeg,
                properties: target == .png ? [:] : [.compressionFactor: 0.9]
            )
        else {
            return nil
        }

        do {
            try data.write(to: output)
            return output
        } catch {
            return nil
        }
    }

    // MARK: - Text

    /// Paginated A4-ish PDF (US Letter) with a one-inch-ish margin.
    private static func textToPDF(_ url: URL, _ output: URL) -> URL? {

        let text: NSAttributedString

        if let attributed = Self.loadDocument(url) {
            text = attributed
        } else if let plain = try? String(contentsOf: url, encoding: .utf8) {
            text = NSAttributedString(
                string: plain,
                attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
        } else {
            return nil
        }

        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let margin: CGFloat = 54
        let body = page.insetBy(dx: margin, dy: margin)

        var mediaBox = page

        guard let context = CGContext(output as CFURL, mediaBox: &mediaBox, nil) else { return nil }

        let framesetter = CTFramesetterCreateWithAttributedString(text)

        var location = 0

        repeat {

            context.beginPDFPage(nil)

            let path = CGPath(rect: body, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: location, length: 0), path, nil)

            CTFrameDraw(frame, context)

            let visible = CTFrameGetVisibleStringRange(frame)

            context.endPDFPage()

            guard visible.length > 0 else { break }

            location += visible.length

        } while location < text.length

        context.closePDF()

        return output
    }

    /// Opens a document with whichever reader fits its extension (the
    /// automatic one doesn't always recognise Word files).
    private static func loadDocument(_ url: URL) -> NSAttributedString? {

        let types: [NSAttributedString.DocumentType]

        switch url.pathExtension.lowercased() {
        case "docx": types = [.officeOpenXML]
        case "doc": types = [.docFormat]
        case "odt": types = [.openDocument]
        case "rtf": types = [.rtf]
        case "rtfd": types = [.rtfd]
        case "html", "htm": types = [.html]
        case "webarchive": types = [.webArchive]
        default: types = []
        }

        for type in types {
            if let result = try? NSAttributedString(
                url: url,
                options: [.documentType: type],
                documentAttributes: nil
            ) {
                return result
            }
        }

        return try? NSAttributedString(url: url, options: [:], documentAttributes: nil)
    }

    // MARK: - Audio / video

    private static func export(
        _ url: URL,
        _ output: URL,
        preset: String,
        type: AVFileType
    ) async -> URL? {

        let asset = AVURLAsset(url: url)

        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { return nil }

        session.outputURL = output
        session.outputFileType = type

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { continuation.resume() }
        }

        return session.status == .completed ? output : nil
    }
}
