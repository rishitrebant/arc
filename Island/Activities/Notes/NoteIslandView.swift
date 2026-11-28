import SwiftUI

/// Renders `NoteActivity`: a pill with the note glyph and a pin, opening
/// on hover into the note with Copy and Unpin.
struct NoteIslandView: View {

    @ObservedObject var activity: NoteActivity
    @ObservedObject private var store: NoteStore
    let isExpanded: Bool

    init(activity: NoteActivity, isExpanded: Bool) {
        self.activity = activity
        self.isExpanded = isExpanded
        self._store = ObservedObject(wrappedValue: activity.store)
    }

    private var accent: Color { NoteActivity.accent }

    var body: some View {

        IslandMorphSurface(
            isExpanded: isExpanded,
            compactSize: activity.compactSize,
            expandedSize: activity.expandedSize
        ) {
            compact
        } expanded: {
            expandedPanel
        }
        .animation(AnimationTokens.shapeSpring, value: activity.expandedSize.height)
    }

    // MARK: - Compact

    private var compact: some View {

        HStack(spacing: 0) {

            Image(systemName: "note.text")
                .font(.system(size: DesignTokens.StatusPillMetrics.glyphSize, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: DesignTokens.StatusPillMetrics.iconSlot)

            Spacer(minLength: 0)

            Image(systemName: "pin.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent.opacity(0.7))
                .rotationEffect(.degrees(30))
                .frame(width: DesignTokens.StatusPillMetrics.iconSlot)
        }
        .padding(.horizontal, DesignTokens.StatusPillMetrics.edgePadding)
    }

    // MARK: - Expanded

    private var expandedPanel: some View {

        VStack(spacing: 0) {

            // Reserves the physical notch cutout.
            Color.clear
                .frame(height: DesignTokens.FileDropMetrics.notchKeepClearHeight)

            HStack(alignment: .top, spacing: 12) {

                Text(store.pinned?.text ?? "")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.Color.primaryText)
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {

                    disc("doc.on.doc", label: "Copy") {
                        if let text = store.pinned?.text {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }

                    disc("pin.slash.fill", label: "Unpin") {
                        store.unpin()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .topLeading) {
            LauncherBackButton()
        }
    }

    private func disc(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {

        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Color.primaryText)
                .frame(width: 28, height: 28)
                .background(Circle().fill(DesignTokens.Color.controlDisc))
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(label)
    }
}
