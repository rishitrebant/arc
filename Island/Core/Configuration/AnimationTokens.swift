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
    static let shapeDuration: TimeInterval = 0.22
    static let shapeDampingFraction: Double = 0.84
    static var shapeSpring: Animation { .spring(response: shapeDuration, dampingFraction: shapeDampingFraction) }

    /// The island growing out of the notch when an activity arrives:
    /// a touch of bounce at the end, like the Dynamic Island.
    static var enterSpring: Animation { .spring(response: 0.28, dampingFraction: 0.78) }

    /// The island shrinking back into the notch: no bounce — it should
    /// settle into the notch, not rebound out of it.
    static var exitSpring: Animation { .spring(response: 0.22, dampingFraction: 1) }

    /// How long the exit spring takes to be safely out of sight.
    static let exitSettleDuration: TimeInterval = 0.26

    /// One activity handing the island to another (launcher → music,
    /// timer → charging…): a springier, slower morph than hover, with a
    /// visible settle — the Dynamic Island's signature bounce.
    static var handoverSpring: Animation { .spring(response: 0.36, dampingFraction: 0.74) }

    /// Chooses the hand-over spring by direction: bouncy when the island
    /// grows or stays the same height, critically damped when it shrinks.
    static func handover(from old: CGSize, to new: CGSize) -> Animation {
        new.height < old.height - 0.5
            ? .spring(response: 0.3, dampingFraction: 1)
            : handoverSpring
    }

    /// Content waits for the shape to open up before it fades in.
    static let contentRevealDelay: TimeInterval = 0.04

    /// On collapse, content must clear out FIRST, and the shape only
    /// shrinks once it does — otherwise text/controls would visibly clip
    /// as the shape shrinks out from under them.
    static let collapseShapeDelay: TimeInterval = 0.06

    /// Required sequence is directional, not symmetric: on expand, the
    /// shape leads (grows immediately) and content follows once there's
    /// room. On collapse, content clears first (see `collapseShapeDelay`).
    static func shapeMorph(isExpanding: Bool) -> Animation {
        isExpanding ? shapeSpring : collapseSpring.delay(collapseShapeDelay)
    }

    /// Anything shrinking: critically damped, so it eases into its final
    /// size and never dips below it. (A bouncy spring overshoots its
    /// target — fine when growing, but shrinking it would make the
    /// island briefly smaller than the pill it is becoming.)
    static var collapseSpring: Animation { .spring(response: shapeDuration, dampingFraction: 1) }

    /// Builds the asymmetric insertion/removal transition for one piece of
    /// expanded-only content (header text, progress bar, controls).
    /// `insertDelay` staggers entrance after the shape/artwork have started
    /// growing; `removeDelay` staggers exit so later-appearing elements
    /// leave first — the reverse of the entrance order, per spec.
    static func contentTransition(insertDelay: Double, removeDelay: Double) -> AnyTransition {
        .asymmetric(
            insertion: .opacity
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
    static let hoverActivationDelay: TimeInterval = 0.35

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
    
    /// How long the "charger plugged in" pill stays before returning
    /// the island to whatever was there. Longer than
    /// `transientDisplayDuration` because it carries a sentence and a
    /// number the user has to actually read — closer to how long the
    /// iPhone holds its charging moment.
    static let chargingDisplayDuration: TimeInterval = 3.0

    /// How long the low-battery alert waits for a click before going
    /// away. Long on purpose — it's asking the user to do something,
    /// and the cursor has to travel to the notch first. (It also never
    /// closes while the cursor is on it.)
    static let lowBatteryDisplayDuration: TimeInterval = 8.0

    /// How long the "Bluetooth device connected" pill stays before
    /// returning the island (never while the cursor is on it).
    static let bluetoothDisplayDuration: TimeInterval = 4.0

    /// How long the "Focus on / off" pill stays.
    static let focusDisplayDuration: TimeInterval = 2.2

    /// How long the "sound output changed" pill stays.
    static let audioOutputDisplayDuration: TimeInterval = 3.0

    /// How long the "meeting starting" pill stays (never while hovered).
    static let calendarDisplayDuration: TimeInterval = 8.0

    /// How long the "microphone / camera / screen recording" pill stays.
    static let privacyDisplayDuration: TimeInterval = 3.5

    /// How long the green check shows after a download finishes.
    static let downloadsCompletionDuration: TimeInterval = 1.8

    /// How long the "Caps Lock On/Off" pill stays.
    static let capsLockDisplayDuration: TimeInterval = 1.6

    /// How long a finished timer keeps ringing the island before it
    /// dismisses itself, and the gap between repeated chimes.
    static let timerFinishedDuration: TimeInterval = 60
    static let timerChimeInterval: TimeInterval = 3

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
