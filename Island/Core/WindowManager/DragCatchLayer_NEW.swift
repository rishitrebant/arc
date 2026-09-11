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

        ZStack(alignment: .top) {

            // Per direct request: "a glow should appear near the notch
            // as soon as the file is brought to it" — immediate, before
            // the full panel commits to showing half a second later.
            // Lives here rather than in `FileDropIslandView` for the
            // same reason the drop target itself does: this layer is
            // always present, even while Music still owns the island.
            if activity.isDragNear {
                notchGlow
                    .transition(.opacity)
            }

            Color.clear
                .frame(
                    width: DesignTokens.FileDropMetrics.dragCatchZoneWidth,
                    // Deliberately kept at the narrow initial height
                    // (90pt), not grown to the full panel size — an
                    // earlier attempt at that caused a real regression:
                    // this view is always present in the window,
                    // including while Music owns the island, and
                    // growing its own interactive footprint that much
                    // risked interfering with Music's own controls
                    // sitting in the same window. The "loses tracking
                    // once the panel is deeper than 90pt" bug this was
                    // trying to fix is handled in `FileDropIslandView`
                    // instead — that view (and its own `.onDrop`) only
                    // exists at all while FileDrop already owns the
                    // island, so it can never overlap with Music.
                    height: DesignTokens.FileDropMetrics.dragCatchZoneHeight
                )
                .contentShape(Rectangle())
                .onDrop(
                    of: [.fileURL],
                    isTargeted: Binding(
                        get: { activity.isDragNear },
                        set: { near in
                            if near {
                                if !activity.isDragNear {
                                    // Item count arrives async per-provider
                                    // below; start with what we know now so
                                    // the glow appears immediately rather
                                    // than waiting.
                                    activity.dragEntered(itemCount: 1)
                                }
                            } else {
                                activity.dragExited()
                            }
                        }
                    )
                ) { providers in

                    resolveDroppedFiles(from: providers) { files in
                        guard !files.isEmpty else { return }
                        activity.dropOnShelf(files: files)
                    }

                    return true
                }
        }
        .animation(.easeOut(duration: 0.2), value: activity.isDragNear)
    }

    // "Projected from the notch, below" — per direct request, not a
    // plain symmetric glow. A soft, top-to-bottom fading shape whose
    // TOP edge sits flush against the notch's own bottom edge (27pt,
    // per direct measurement), extending downward from there and
    // fading out — reads as light spilling down FROM the notch, rather
    // than a blob that happens to surround it on all sides (including
    // above, where there's nothing to glow from).
    private var notchGlow: some View {
        Ellipse()
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.45),
                        Color.white.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .frame(width: 230, height: 100)
            .blur(radius: 12)
            .offset(y: DesignTokens.FileDropMetrics.notchHeight - 40)
            .allowsHitTesting(false)
    }
}

/// One file resolved from a drag session — its now-persisted URL
/// (see `ShelfFileStore`) alongside its real display name.
struct DroppedFile {
    let url: URL
    let displayName: String
}

/// Shared by `DragCatchLayer` and the two tiles inside the expanded
/// drag-choice panel — resolves `NSItemProvider`s to file URLs AND
/// copies each into `ShelfFileStore`'s managed temp directory (see
/// `ShelfItem`'s doc comment for why a bare reference isn't enough).
func resolveDroppedFiles(
    from providers: [NSItemProvider],
    completion: @escaping ([DroppedFile]) -> Void
) {

    guard !providers.isEmpty else {
        completion([])
        return
    }

    var resolved: [DroppedFile] = []
    let group = DispatchGroup()

    for provider in providers {

        guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { continue }

        group.enter()

        let suggestedName = provider.suggestedName

        provider.loadItem(
            forTypeIdentifier: UTType.fileURL.identifier
        ) { item, _ in

            // `loadItem`'s completion can fire on an arbitrary background
            // queue, and can do so for multiple providers concurrently —
            // mutating `resolved` from more than one thread at once would
            // be a real data race, not just untidy. Funnel every mutation
            // (and the copy itself) through the main queue so it's always
            // serialized.
            let sourceURL: URL? = {
                if let data = item as? Data {
                    return URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    return url
                }
                return nil
            }()

            DispatchQueue.main.async {
                if let sourceURL,
                   let persisted = ShelfFileStore.persist(
                       sourceURL: sourceURL,
                       suggestedName: suggestedName
                   ) {
                    resolved.append(
                        DroppedFile(
                            url: persisted.url,
                            displayName: persisted.displayName
                        )
                    )
                }
                group.leave()
            }
        }
    }

    group.notify(queue: .main) {
        completion(resolved)
    }
}
