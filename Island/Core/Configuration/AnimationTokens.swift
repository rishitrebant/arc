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

    /// The spring driving the island body/artwork/waveform morph itself —
    /// the shared-geometry elements. ~200ms per Apple's Dynamic Island
    /// timing target (180-220ms), spring rather than a fixed ease so it
    /// feels physically responsive rather than mechanically animated.
    static let shapeDuration: TimeInterval = 0.20
    static let shapeDampingFraction: Double = 0.88
    static var shapeSpring: Animation { .spring(response: shapeDuration, dampingFraction: shapeDampingFraction) }

    /// On collapse, content must clear out FIRST, and the shape only
    /// shrinks once it does — otherwise text/controls would visibly clip
    /// as the shape shrinks out from under them.
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

    /// Drives the hover "prime" shadow — the instant, no-delay affordance
    /// that appears the moment a hover starts (and disappears the moment
    /// it ends), independent of `hoverActivationDelay`/
    /// `hoverDeactivationDelay` above, which gate the actual expand/
    /// collapse. This is what makes the interaction read as "the island
    /// noticed you" right away, followed by a deliberate pause before it
    /// actually commits to expanding — rather than one silent delay with
    /// no feedback during it.
    static let hoverPrimeTransition = Animation.easeOut(duration: 0.12)

    /// How long transient activities (DND toggle, AirDrop completion) stay
    /// visible before returning to the previous activity or disappearing.
    static let transientDisplayDuration: TimeInterval = 1.6
    
    struct SpringPhysics {
        let mass: CGFloat
        let stiffness: CGFloat
        let damping: CGFloat
    }

    static let springPhysics = SpringPhysics(
        mass: 1.0,
        stiffness: 180.0,
        damping: 24.0
    )
}
