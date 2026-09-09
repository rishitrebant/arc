import SwiftUI
import UniformTypeIdentifiers

/// An invisible strip, generously sized (`FileDropMetrics.dragCatchZone*`),
/// that's always part of the view hierarchy regardless of which activity
/// currently owns the island — including while Music owns it.
///
/// This is deliberately NOT inside `FileDropIslandView`. That view only
/// exists in the hierarchy once `FileDropActivity` already owns the
/// island — but something has to detect the drag BEFORE that happens,
/// since detecting it is literally what causes `ActivityManager` to hand
/// ownership over in the first place. This layer is that something: it
/// sits alongside `IslandRootView` inside the same window (wired in
/// `AppDelegate.presentIsland`), calling straight into `FileDropActivity`.
struct DragCatchLayer: View {

    @ObservedObject var activity: FileDropActivity

    var body: some View {

        Color.clear
            .frame(
                width: DesignTokens.FileDropMetrics.dragCatchZoneWidth,
                height: DesignTokens.FileDropMetrics.dragCatchZoneHeight
            )
            .contentShape(Rectangle())
            .onDrop(
                of: [.fileURL],
                isTargeted: Binding(
                    get: { activity.isDragHovering },
                    set: { hovering in
                        if hovering {
                            // Item count arrives async per-provider below;
                            // start with what we know now so the panel
                            // appears immediately rather than waiting.
                            if !activity.isDragHovering {
                                activity.dragEntered(itemCount: 1)
                            }
                        } else {
                            activity.dragExited()
                        }
                    }
                )
            ) { providers in

                loadURLs(from: providers) { urls in
                    guard !urls.isEmpty else { return }
                    // A plain drop on the catch zone (not on either tile
                    // inside the expanded panel) defaults to the shelf —
                    // the lower-commitment of the two actions.
                    activity.dropOnShelf(urls: urls)
                }

                return true
            }
    }
}

/// Shared by `DragCatchLayer` and the two tiles inside the expanded
/// drag-choice panel — resolves `NSItemProvider`s to file `URL`s.
func loadURLs(
    from providers: [NSItemProvider],
    completion: @escaping ([URL]) -> Void
) {

    guard !providers.isEmpty else {
        completion([])
        return
    }

    var resolved: [URL] = []
    let group = DispatchGroup()

    for provider in providers {

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { continue }

        group.enter()

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier
        ) { item, _ in

            // `loadItem`'s completion can fire on an arbitrary background
            // queue, and can do so for multiple providers concurrently —
            // mutating `resolved` from more than one thread at once would
            // be a real data race, not just untidy. Funnel every mutation
            // through the main queue so appends are always serialized.
            let url: URL? = {
                if let data = item as? Data {
                    return URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    return url
                }
                return nil
            }()

            DispatchQueue.main.async {
                if let url {
                    resolved.append(url)
                }
                group.leave()
            }
        }
    }

    group.notify(queue: .main) {
        completion(resolved)
    }
}
