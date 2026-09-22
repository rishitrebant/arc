import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Backs the shelf's drag-OUT behavior (used in `FileDropIslandView`
/// in place of the old `.onDrag { ... }` closures).
///
/// CORRECTION from an earlier version of this file: `NSFilePromiseProvider`
/// does NOT inherit from `NSItemProvider` — it conforms to
/// `NSPasteboardWriting` instead — so it can never be returned from
/// SwiftUI's `.onDrag(_:)`, which requires a plain `NSItemProvider`. That
/// modifier structurally can't drive a file promise at all; a promise only
/// works inside a real `NSDraggingSession`, which needs an actual `NSView`
/// as its source. This type is that `NSView`, wrapped for SwiftUI via
/// `NSViewRepresentable`.
///
/// Per direct request: dragging a shelf item out to Finder (or any other
/// drop target) should remove it from the shelf once it's actually been
/// placed somewhere — not just hand over a copy and leave the shelf
/// unchanged. `NSFilePromiseProvider` is still the right mechanism for
/// that (the destination tells us exactly where it wants the file
/// written), it just has to be driven by a real drag source rather than
/// SwiftUI's own `.onDrag`. The promise's `writePromiseTo` completion
/// handler firing successfully IS the "it landed somewhere" signal —
/// that's when `onCompleted` actually removes the shelf item. A
/// cancelled drag, or one dropped somewhere that refuses the file,
/// never calls `writePromiseTo` at all, so the item stays put.
///
/// Usage: apply as an `.overlay(ShelfItemDragSource(item:onCompleted:))`
/// on the exact view that should be draggable — sized to match, so it
/// doesn't swallow clicks meant for anything else nearby (e.g. the
/// shelf item's small delete button, which sits just outside this
/// view's own frame).
struct ShelfItemDragSource: NSViewRepresentable {

    let item: ShelfItem
    let onCompleted: (UUID) -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        view.item = item
        view.onCompleted = onCompleted
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        // Items are re-created (not mutated) whenever `shelfItems`
        // changes, so this keeps the view's copy current across
        // re-renders without needing Equatable-driven diffing here.
        nsView.item = item
        nsView.onCompleted = onCompleted
    }

    final class DragSourceView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {

        var item: ShelfItem?
        var onCompleted: ((UUID) -> Void)?

        // Transparent — this view exists purely to capture the mouse
        // event and drive the drag session; whatever SwiftUI content
        // it's overlaid on is what's actually visible.
        override var isOpaque: Bool { false }

        override func mouseDown(with event: NSEvent) {

            guard let item else { return }

            let fileType =
                UTType(filenameExtension: item.url.pathExtension)?.identifier
                    ?? UTType.data.identifier

            let provider = NSFilePromiseProvider(fileType: fileType, delegate: self)

            let draggingItem = NSDraggingItem(pasteboardWriter: provider)

            let thumbnail = NSWorkspace.shared.icon(forFile: item.url.path)

            draggingItem.setDraggingFrame(bounds, contents: thumbnail)

            beginDraggingSession(with: [draggingItem], event: event, source: self)
        }

        // MARK: - NSDraggingSource

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {

            context == .outsideApplication ? [.copy, .move] : []
        }

        // MARK: - NSFilePromiseProviderDelegate

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            fileNameForType fileType: String
        ) -> String {

            item?.displayName ?? "file"
        }

        func filePromiseProvider(
            _ filePromiseProvider: NSFilePromiseProvider,
            writePromiseTo url: URL,
            completionHandler: @escaping (Error?) -> Void
        ) {

            guard let sourceURL = item?.url else {
                completionHandler(nil)
                return
            }

            do {

                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }

                try FileManager.default.copyItem(at: sourceURL, to: url)

                completionHandler(nil)

                let id = item?.id

                DispatchQueue.main.async { [weak self] in
                    guard let self, let id else { return }
                    self.onCompleted?(id)
                }

            } catch {

                completionHandler(error)
            }
        }

        func operationQueue(
            for filePromiseProvider: NSFilePromiseProvider
        ) -> OperationQueue {

            Self.writeQueue
        }

        /// `NSFilePromiseProvider` requires the actual write to happen
        /// off the main thread — this is that queue, shared across
        /// every in-flight promise rather than one per view instance.
        private static let writeQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()
    }
}
