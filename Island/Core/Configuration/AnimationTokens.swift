import SwiftUI

/// Centralized animation timing and curves.
///
/// Per Engineering Constitution: "Animation timing must never be hardcoded
/// inside feature views. Animation values belong in configuration."
///
/// No durations were specified in the source documents — PRODUCT.md only
/// describes motion qualitatively ("should never feel instant", "should feel
/// 120Hz", "brief duration"). All values below are derived to match that
/// intent and should be tuned against the real Figma prototype/video if one
/// becomes available.
enum AnimationTokens {

    /// Physical spring parameters (mass/stiffness/damping), as opposed to a
    /// SwiftUI-only `Animation` value. SwiftUI's `.spring(response:
    /// dampingFraction:)` is itself just a friendlier front-end for these
    /// same three numbers — so exposing the underlying physics lets a
    /// *non*-SwiftUI animator (see `SpringAnimator`, driving the AppKit
    /// window frame) reproduce the identical motion curve, tick for tick,
    /// instead of approximating it with a fixed-duration ease curve.
    ///
    /// This is the actual fix for the window and content visibly
    /// disagreeing about motion: previously the SwiftUI content used a
    /// spring while the AppKit window used `CAMediaTimingFunction(name:
    /// .easeOut)` with a matching *duration* but a completely different
    /// *curve shape* — same length, different shape, so they only ever
    /// agreed at the start and end and visibly drifted apart in between.
    struct SpringPhysics {
        var mass: CGFloat = 1
        var stiffness: CGFloat
        var damping: CGFloat

        /// Derives physical stiffness/damping from the same
        /// response/dampingFraction parameterization SwiftUI's
        /// `.spring(response:dampingFraction:)` uses, so a value tuned by
        /// feel in SwiftUI (where "response" reads as an intuitive
        /// duration-ish knob) can be reused verbatim by an AppKit-side
        /// animator with zero manual re-tuning.
        static func from(response: TimeInterval, dampingFraction: Double, mass: CGFloat = 1) -> SpringPhysics {
            let stiffness = pow(2 * .pi / response, 2) * mass
            let damping = 4 * .pi * dampingFraction * mass / response
            return SpringPhysics(mass: mass, stiffness: stiffness, damping: damping)
        }
    }

    /// The spring driving the island body/artwork/waveform morph itself —
    /// the shared-geometry elements. ~200ms per Apple's Dynamic Island
    /// timing target (180-220ms), spring rather than a fixed ease so it
    /// feels physically responsive rather than mechanically animated.
    static let shapeDuration: TimeInterval = 0.20
    static let shapeDampingFraction: Double = 0.88
    static var shapeSpring: Animation { .spring(response: shapeDuration, dampingFraction: shapeDampingFraction) }

    /// The same spring as `shapeSpring`, expressed as raw physics for
    /// `WindowManager`'s `SpringAnimator` to consume directly. Keep this in
    /// lockstep with `shapeDuration`/`shapeDampingFraction` above — it's
    /// derived from them, not an independent value, on purpose.
    static var shapePhysics: SpringPhysics {
        .from(response: shapeDuration, dampingFraction: shapeDampingFraction)
    }

    /// On collapse, content must clear out FIRST, and the shape only
    /// shrinks once it does — otherwise text/controls would visibly clip
    /// as the shape shrinks out from under them. This delay is shared by
    /// both the SwiftUI shape morph AND the AppKit window-frame animation
    /// (see `WindowManager.animateToSize`), so the window doesn't clip the
    /// still-full-size content during that gap.
    static let collapseShapeDelay: TimeInterval = 0.06

    /// Required sequence is directional, not symmetric: on expand, the
    /// shape leads (grows immediately) and content follows once there's
    /// room. On collapse, content clears first (see `collapseShapeDelay`).
    static func shapeMorph(isExpanding: Bool) -> Animation {
        isExpanding ? shapeSpring : shapeSpring.delay(collapseShapeDelay)
    }

    /// Builds the asymmetric insertion/removal transition for one piece of
    /// expanded-only content (header text, progress bar, controls).
    /// `insertDelay` staggers entrance after the shape/artwork have started
    /// growing; `removeDelay` staggers exit so later-appearing elements
    /// leave first — the reverse of the entrance order, per spec.
    static func contentTransition(insertDelay: Double, removeDelay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -3))
                .animation(shapeSpring.delay(insertDelay)),
            removal: .opacity
                .animation(.easeOut(duration: 0.12).delay(removeDelay))
        )
    }

    /// Used when a higher-priority activity takes over the island
    /// (e.g. incoming call interrupting music).
    static let ownershipChange = Animation.timingCurve(0.32, 0.94, 0.6, 1.0, duration: 0.36)

    /// Fast state update within the same activity (e.g. play/pause icon swap).
    static let stateUpdate = Animation.easeInOut(duration: 0.18)

    /// Per "Hover Philosophy": expansion must feel earned, never accidental —
    /// but Apple's own hover-intent windows are short. 0.35s read as
    /// sluggish; this is a deliberate but brief pause, not a lag.
    static let hoverActivationDelay: TimeInterval = 0.15

    /// Collapse should feel calm without dragging — shorter than before,
    /// still a touch slower than activation so it doesn't feel like a flinch.
    static let hoverDeactivationDelay: TimeInterval = 0.1

    /// How long transient activities (DND toggle, AirDrop completion) stay
    /// visible before returning to the previous activity or disappearing.
    static let transientDisplayDuration: TimeInterval = 1.6
}
