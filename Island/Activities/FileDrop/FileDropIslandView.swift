import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Renders `FileDropActivity`'s states:
///   - compact: a file preview on the left (matching where Music shows
///     album art) and a static shelf icon on the right (matching where
///     Music shows the waveform)
///   - expanded: one unified panel that's simultaneously the drop
///     target AND the shelf grid — see `FileDropActivity`'s type doc
///     for why the old two-tile shelf/AirDrop split was replaced with
///     this plus a dedicated AirDrop button
///
/// Same fixed-canvas architecture as `MusicIslandView`: this view's own
/// outer frame always reports the SAME size regardless of internal
/// state (matching Music's own 390×200, since that's still the largest
/// activity and what `WindowManager`'s window is actually sized around)
/// — visible content sizes/positions itself within that fixed frame
/// instead. This is what keeps activity-to-activity ownership changes
/// from re-triggering the parent-recentering flakiness that same trick
/// was built to eliminate for Music's own compact↔expanded morph.
struct FileDropIslandView: View {

    @ObservedObject var activity: FileDropActivity
    let isExpanded: Bool

    @State private var isTargetedForDrop = false

    /// Per direct request: use the exact same morph as Music's own
    /// compact↔expanded transition, rather than a custom-tuned variant
    /// — a previous attempt at a "gentler" spring for FileDrop's larger
    /// size swing is reverted here in favor of literally matching
    /// `AnimationTokens.shapeMorph`, used directly below.

    /// `isExpanded` alone only reflects hover — IslandRootView has no
    /// idea a drop just happened, or that a drag has committed to
    /// showing the panel. Both cases are folded in here, used
    /// everywhere below instead of the raw `isExpanded` parameter.
    /// (Deliberately NOT `isDragNear` — that's the glow-only phase,
    /// which layers on top of whatever's already showing rather than
    /// taking over the island; see `FileDropActivity`'s type doc.)
    private var effectiveExpanded: Bool {
        isExpanded || activity.isShowingFreshReveal || activity.isDragHovering
    }

    // Shared canvas size every activity's outer view reports, regardless
    // of its own content size — see the type doc above. Now that
    // FileDrop's "has items" state (367×225) is taller than Music's own
    // 390×200, this reads the genuinely shared constant rather than
    // Music's own metrics directly, so both stay consistent with
    // whichever is currently largest.
    private var canvasSize: CGSize {
        DesignTokens.sharedCanvasSize
    }

    private var visibleSize: CGSize {
        guard effectiveExpanded else {
            return CGSize(
                width: DesignTokens.FileDropMetrics.compactWidth,
                height: DesignTokens.FileDropMetrics.compactHeight
            )
        }
        // Two expanded sizes, not one — see `FileDropActivity.expandedSize`'s
        // doc comment. Reading it directly here (rather than duplicating
        // the same empty/has-items branch) keeps this single source of
        // truth for which size applies right now.
        return activity.expandedSize
    }

    private var horizontalInset: CGFloat {
        (canvasSize.width - visibleSize.width) / 2
    }

    var body: some View {

        ZStack(alignment: .topLeading) {

            IslandShape(
                topRadius: effectiveExpanded ? DesignTokens.Shape.expandedTopRadius : DesignTokens.Shape.compactTopRadius,
                bottomRadius: effectiveExpanded ? DesignTokens.Shape.expandedBottomRadius : DesignTokens.Shape.compactBottomRadius
            )
            .fill(DesignTokens.Color.islandBackground)
            // "Make the colour change to wherever the file is taken, so
            // it looks like it's accepting" — the whole panel tints
            // while a drag is actively targeted over it, standard
            // drop-acceptance affordance (same idea as Finder
            // highlighting a folder you're dragging onto).
            .overlay {
                if isTargetedForDrop {
                    IslandShape(
                        topRadius: DesignTokens.Shape.expandedTopRadius,
                        bottomRadius: DesignTokens.Shape.expandedBottomRadius
                    )
                    .fill(Color.accentColor.opacity(0.22))
                }
            }
            .frame(width: visibleSize.width, height: visibleSize.height)
            .position(x: canvasSize.width / 2, y: visibleSize.height / 2)

            Group {
                if effectiveExpanded {
                    expandedPanel
                } else {
                    compactRow
                }
            }
            .frame(width: visibleSize.width, height: visibleSize.height)
            .offset(x: horizontalInset, y: 0)
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
        .animation(AnimationTokens.shapeMorph(isExpanding: effectiveExpanded), value: effectiveExpanded)
        // Separate trigger, deliberately — the empty→has-items size
        // change (315×158 → 367×225, revealing the Shelf/AirDrop
        // buttons) can happen while `effectiveExpanded` is ALREADY true
        // the whole time (a drop landing mid-reveal doesn't toggle that
        // bool), so it needs its own animation trigger to actually
        // animate smoothly rather than snap. Per direct request: "the
        // island expanding smoothly" when the buttons appear.
        //
        // FIX: this used to hardcode `isExpanding: true` regardless of
        // the actual direction — correct for the empty→has-items growth
        // this was built for, but wrong for the reverse (e.g. hitting
        // the trash button while the panel's open empties the shelf,
        // which is a SHRINK, not a grow). Using the wrong direction's
        // curve/timing (`AnimationTokens.shapeMorph` uses genuinely
        // different timing for each) on the same underlying geometry
        // that the trigger above is ALSO animating is exactly the kind
        // of mismatch that produces glitchy, inconsistent-looking
        // motion — a very plausible contributor to the reported
        // "closes/opens on the X axis only" symptom. Using
        // `effectiveExpanded` here too keeps both triggers pointed at
        // the same, correct direction always.
        .animation(AnimationTokens.shapeMorph(isExpanding: effectiveExpanded), value: activity.shelfItems.isEmpty)
        .animation(.easeOut(duration: 0.15), value: isTargetedForDrop)
        .onDrop(
            of: [.fileURL],
            isTargeted: Binding(
                get: { isTargetedForDrop },
                set: { targeted in
                    isTargetedForDrop = targeted
                    if targeted {
                        // Keeps the drag state alive while the cursor is
                        // anywhere within this (much taller, once
                        // expanded) panel. Safe to do here specifically
                        // — this view only exists at all while FileDrop
                        // already owns the island, so it can never
                        // overlap with Music. Without this,
                        // `DragCatchLayer`'s own much smaller 90pt catch
                        // strip would lose the drag the moment the
                        // cursor moved deeper into the panel, even
                        // though it never actually left the visible,
                        // interactive area — that's what was causing
                        // the panel to repeatedly collapse mid-drag.
                        activity.dragEntered(itemCount: activity.draggedItemCount)
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

    // MARK: - Compact
    //
    // X positions use Music's OWN constants (`compactEdgePadding`,
    // `compactIconSize`) — per direct request, this keeps left/right
    // placement identical to Music's compact layout by construction. Y
    // uses THIS activity's own `compactContentCenterY` (true geometric
    // center) instead — see that constant's doc comment for why
    // reusing Music's own Y value doesn't apply here.

    private var compactRow: some View {

        ZStack {

            // LEFT — most recently added file's preview, where Music
            // shows album art. Local coordinates only, no extra
            // centering offset — `compactRow` already renders inside a
            // frame that's exactly `visibleSize` (263 wide) and is
            // already centered within the shared 390-wide canvas by the
            // `.offset(x: horizontalInset)` wrapper around it in `body`.
            // Adding a SECOND centering offset here (the removed
            // `compactHorizontalInset` term) double-counted that shift —
            // which is exactly what put this icon under the notch
            // instead of to its left.
            if let item = activity.shelfItems.last {
                fileIcon(for: item.url)
                    .frame(
                        width: DesignTokens.MusicMetrics.compactIconSize,
                        height: DesignTokens.MusicMetrics.compactIconSize
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        ShelfItemDragSource(item: item) { id in
                            activity.completeExport(id)
                        }
                    )
                    .position(
                        x: DesignTokens.MusicMetrics.compactEdgePadding
                            + DesignTokens.MusicMetrics.compactIconSize / 2,
                        y: DesignTokens.FileDropMetrics.compactContentCenterY
                    )
            }

            // RIGHT — static shelf logo, where Music shows the waveform.
            // Same fix — local coordinates only.
            Image(systemName: "tray.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .position(
                    x: DesignTokens.FileDropMetrics.compactWidth
                        - DesignTokens.MusicMetrics.compactEdgePadding
                        - DesignTokens.MusicMetrics.compactIconSize / 2,
                    y: DesignTokens.FileDropMetrics.compactContentCenterY
                )
        }
    }

    // MARK: - Expanded (unified drop-zone + shelf grid)

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout — per direct
            // measurement, nothing renders in this region at all.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            // Top-right trash — "discard the shelf" — only shown once
            // there's something TO discard.
            if !activity.shelfItems.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        activity.clearShelf()
                    } label: {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, DesignTokens.FileDropMetrics.shelfGridPadding)
                .padding(.top, 6)
                .padding(.bottom, 6)
            }

            // The inset "well" — per direct request, gives the
            // content area its own distinct rounded surface instead of
            // sitting flush against the panel's own black background.
            // Wraps BOTH the empty-state placeholder and the populated
            // grid, so the panel always has this same chrome regardless
            // of content.
            wellContent
                .padding(.horizontal, DesignTokens.FileDropMetrics.shelfGridPadding)
                .padding(.top, activity.shelfItems.isEmpty ? 6 : 0)
                .padding(.bottom, activity.shelfItems.isEmpty ? 16 : 0)

            if !activity.shelfItems.isEmpty {

                // Per direct request, not visible at all until this
                // point; this whole branch only exists once there's at
                // least one item, and the smooth grow into the taller
                // canvas size that makes room for it is handled by the
                // `.animation` keyed to `shelfItems.isEmpty` up in
                // `body`.
                bottomActionRow
            }
        }
    }

    private var wellContent: some View {

        Group {
            if activity.shelfItems.isEmpty {

                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 26, weight: .medium))
                    Text("Drop files to add them to the shelf")
                        .font(.system(size: 12))
                }
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {

                shelfGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(
                cornerRadius: DesignTokens.FileDropMetrics.shelfWellCornerRadius,
                style: .continuous
            )
            .fill(DesignTokens.Color.shelfWellBackground)
        )
    }

    private var bottomActionRow: some View {

        HStack(spacing: DesignTokens.FileDropMetrics.bottomButtonSpacing) {

            // "Shelf" — items are already auto-saved to the shelf the
            // moment they're dropped, so this isn't a commit action;
            // it's just "done, put this away" — collapses the panel
            // early rather than waiting out the rest of the auto-reveal
            // timer. Items themselves are untouched.
            Button {
                activity.dismissExpandedState()
            } label: {
                Text("Shelf")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignTokens.FileDropMetrics.bottomButtonHeight)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.27, green: 0.27, blue: 0.28))  // derived — eyeballed from the shelf reference screenshot
                    )
            }
            .buttonStyle(.plain)

            // Per direct request: drag multiple files in, then hit this
            // to hand the whole current shelf to the real system
            // AirDrop sheet.
            Button {
                activity.airDropShelfItems()
            } label: {
                Text("AirDrop")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(red: 0.55, green: 0.78, blue: 1.0))
                    .frame(maxWidth: .infinity)
                    .frame(height: DesignTokens.FileDropMetrics.bottomButtonHeight)
                    .background(
                        Capsule()
                            .fill(Color(red: 0.11, green: 0.15, blue: 0.24))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, DesignTokens.FileDropMetrics.shelfGridPadding)
        .padding(.bottom, 16)
        .padding(.top, 10)
    }

    private var shelfGrid: some View {

        let columns = [
            GridItem(
                .adaptive(minimum: DesignTokens.FileDropMetrics.shelfItemSize),
                spacing: DesignTokens.FileDropMetrics.shelfGridSpacing
            )
        ]

        return ScrollView {
            LazyVGrid(columns: columns, spacing: DesignTokens.FileDropMetrics.shelfGridSpacing) {
                ForEach(activity.shelfItems) { item in
                    shelfItemView(item)
                }
            }
            .padding(DesignTokens.FileDropMetrics.shelfGridPadding)
        }
        // Only actually scrolls once the grid genuinely overflows the
        // available space — no bounce/rubber-band feel for a handful
        // of items that already fit, which is what made this feel
        // "unnecessarily scrollable."
        .scrollBounceBehavior(.basedOnSize)
    }

    private func shelfItemView(_ item: ShelfItem) -> some View {

        VStack(spacing: 4) {

            ZStack(alignment: .topTrailing) {

                fileIcon(for: item.url)
                    .frame(
                        width: DesignTokens.FileDropMetrics.shelfItemSize,
                        height: DesignTokens.FileDropMetrics.shelfItemSize
                    )
                    .background(
                        RoundedRectangle(
                            cornerRadius: DesignTokens.FileDropMetrics.shelfItemCornerRadius,
                            style: .continuous
                        )
                        .fill(Color.white.opacity(0.08))
                    )
                    // Drag back OUT to anywhere — Finder, another app,
                    // the Desktop. Backed by a real AppKit drag source
                    // (see `ShelfItemDragSource`) rather than SwiftUI's
                    // `.onDrag`, which can't drive a file promise. Uses
                    // `completeExport`, NOT `removeShelfItem` — the file
                    // was actually delivered to this new destination, so
                    // it shouldn't also be restored to where it
                    // originally came from.
                    .overlay(
                        ShelfItemDragSource(item: item) { id in
                            activity.completeExport(id)
                        }
                    )

                // Delete affordance — removes our own copy from the
                // shelf (see `ShelfFileStore`); has no effect on
                // wherever the file was originally dragged from.
                Button {
                    activity.removeShelfItem(item.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 6, y: -6)
            }

            Text(item.displayName)
                .font(.system(size: 10))
                .foregroundStyle(DesignTokens.Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: DesignTokens.FileDropMetrics.shelfItemSize)
        }
    }

    // MARK: - Shared

    private func fileIcon(for url: URL) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .scaledToFit()
    }
}
