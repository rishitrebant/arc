import SwiftUI

/// Stable Apple-style forward/backward transport icon.
///
/// The icon always shows both chevrons. A tap gives the entire transport
/// glyph a very small directional nudge instead of cycling individual
/// chevrons through hidden slots, which prevents the old "one arrow
/// disappears after repeated taps" bug.
struct SkipChevronsIcon: View {

    let forward: Bool
    let trigger: Int

    /// Matches the previous transport-button visual weight.
    var size: CGFloat = 20

    @State private var pressScale: CGFloat = 1.0
    @State private var pressOffset: CGFloat = 0

    private var symbolName: String {
        forward
            ? "forward.fill"
            : "backward.fill"
    }

    var body: some View {

        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .font(
                .system(
                    size: size,
                    weight: .medium
                )
            )
            .foregroundStyle(.white)
            .scaleEffect(pressScale)
            .offset(
                x:
                    pressOffset
            )
            .frame(
                width: 34,
                height: 34
            )
            .onChange(
                of: trigger
            ) { _, _ in

                let direction: CGFloat =
                    forward ? 1 : -1

                withAnimation(
                    .easeOut(
                        duration: 0.09
                    )
                ) {
                    pressScale = 0.82
                    pressOffset =
                        direction * 2.5
                }

                DispatchQueue.main.asyncAfter(
                    deadline:
                        .now() + 0.09
                ) {
                    withAnimation(
                        .easeOut(
                            duration: 0.13
                        )
                    ) {
                        pressScale = 1.0
                        pressOffset = 0
                    }
                }
            }
    }
}
