import SwiftUI

/// Centralized animation timing and curves.
enum AnimationTokens {

    struct SpringPhysics {
        var mass: CGFloat = 1
        var stiffness: CGFloat
        var damping: CGFloat

        static func from(response: TimeInterval, dampingFraction: Double, mass: CGFloat = 1) -> SpringPhysics {
            let stiffness = pow(2 * .pi / response, 2) * mass
            let damping = 4 * .pi * dampingFraction * mass / response
            return SpringPhysics(mass: mass, stiffness: stiffness, damping: damping)
        }
    }

    // MARK: - The shape/window morph
    //
    // response 0.38 / damping 0.78 settles in ~600ms with ~2pt of
    // overshoot at the end — slow enough to read as deliberate, springy
    // enough to feel alive rather than mechanical. (0.20 / 0.88, the
    // previous values, settled in 350ms with ZERO overshoot — a fast,
    // perfectly critically-damped snap. Correct spring math, wrong feel:
    // Apple's actual island morph is closer to half a second with a
    // whisper of bounce, not a quarter second of a stiff snap.)
    static let shapeDuration: TimeInterval = 0.38
    static let shapeDampingFraction: Double = 0.78
    static var shapeSpring: Animation { .spring(response: shapeDuration, dampingFraction: shapeDampingFraction) }
    static var shapePhysics: SpringPhysics { .from(response: shapeDuration, dampingFraction: shapeDampingFraction) }

    // Content must clear before the shape shrinks on collapse — widened
    // a touch (0.06 -> 0.10) so it's actually perceptible as a beat, not
    // a rounding error.
    static let collapseShapeDelay: TimeInterval = 0.10

    static func shapeMorph(isExpanding: Bool) -> Animation {
        isExpanding ? shapeSpring : shapeSpring.delay(collapseShapeDelay)
    }

    static func contentTransition(insertDelay: Double, removeDelay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -3))
                .animation(shapeSpring.delay(insertDelay)),
            removal: .opacity
                .animation(.easeOut(duration: 0.12).delay(removeDelay))
        )
    }

    static let ownershipChange = Animation.timingCurve(0.32, 0.94, 0.6, 1.0, duration: 0.36)
    static let stateUpdate = Animation.easeInOut(duration: 0.18)

    // MARK: - Hover intent
    //
    // The whole point of a hover delay is "the user meant this, this
    // wasn't a passing cursor" — 0.15s barely registers as a pause at
    // all. Apple's own hover-intent thresholds (Dock magnification, Mission
    // Control) sit closer to 0.3s. Widened to actually feel like a
    // deliberate held moment, not a rounding error before the snap.
    static let hoverActivationDelay: TimeInterval = 0.35
    static let hoverDeactivationDelay: TimeInterval = 0.22

    // The instant "noticed you" shadow — still immediate/no-delay in
    // WHEN it fires, but the fade itself is slower now (0.12 -> 0.22) so
    // it reads as a soft lift instead of a flicker.
    static let hoverPrimeTransition = Animation.easeOut(duration: 0.22)

    static let transientDisplayDuration: TimeInterval = 1.6
}
