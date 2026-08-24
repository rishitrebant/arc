import AppKit
import QuartzCore

/// Drives a `CGSize` value toward a target using real spring physics
/// (mass/stiffness/damping), sampled every frame via a display-synced
/// timer, so an AppKit consumer (see `WindowManager`) can move in true
/// lockstep with a SwiftUI `matchedGeometryEffect` spring using the same
/// `AnimationTokens.SpringPhysics` values.
///
/// This exists to satisfy the single most important motion principle in
/// the design language doc — interruptibility: a running animation must
/// be redirectable mid-flight, continuing from its *live* position and
/// velocity, never snapping or restarting from the old target. Width and
/// height are integrated as two independent 1D springs (matching the
/// doc's guidance to decompose multi-axis motion into independent
/// per-axis springs rather than one coupled 2D spring).
@MainActor
final class SpringAnimator {

    typealias Physics = AnimationTokens.SpringPhysics

    private struct Axis {
        var value: CGFloat
        var velocity: CGFloat = 0
        var target: CGFloat
    }

    private var width: Axis
    private var height: Axis
    private let physics: Physics

    private var displayTimer: Timer?
    private var lastTickTime: CFTimeInterval?
    private var pendingRetarget: DispatchWorkItem?

    /// Below this, the axis is considered settled. Loose enough to avoid
    /// endlessly ticking on sub-pixel residue, tight enough to never be
    /// visible as a pop to the final value.
    private let positionEpsilon: CGFloat = 0.25
    private let velocityEpsilon: CGFloat = 0.5

    var onUpdate: (CGSize) -> Void = { _ in }
    var onSettle: (() -> Void)?

    init(initialSize: CGSize, physics: Physics) {
        self.width = Axis(value: initialSize.width, target: initialSize.width)
        self.height = Axis(value: initialSize.height, target: initialSize.height)
        self.physics = physics
    }

    var currentSize: CGSize { CGSize(width: width.value, height: height.value) }

    /// Retargets toward `size`. If already animating, this redirects the
    /// in-flight spring — current position and velocity carry straight
    /// through, so there's no visible seam. `delay` postpones *starting*
    /// the retarget (used for the collapse-content-first sequencing) and
    /// is itself cancellable: a later call before the delay elapses simply
    /// replaces it, so rapid hover in/out never queues up stale motion.
    func animate(to size: CGSize, delay: TimeInterval = 0) {
        pendingRetarget?.cancel()
        pendingRetarget = nil

        guard delay > 0 else {
            retarget(to: size)
            return
        }

        let work = DispatchWorkItem { [weak self] in self?.retarget(to: size) }
        pendingRetarget = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Places the value immediately with no motion — for initial layout
    /// only, never for a state change a user could perceive.
    func reset(to size: CGSize) {
        pendingRetarget?.cancel()
        pendingRetarget = nil
        stopLoop()
        width = Axis(value: size.width, target: size.width)
        height = Axis(value: size.height, target: size.height)
        onUpdate(size)
    }

    private func retarget(to size: CGSize) {
        width.target = size.width
        height.target = size.height
        startLoopIfNeeded()
    }

    private func startLoopIfNeeded() {
        guard displayTimer == nil else { return }
        lastTickTime = nil

        // 120Hz cadence with real elapsed-time integration below (not a
        // fixed dt), so motion is correct regardless of actual display
        // refresh rate. Added to `.common` run loop mode specifically —
        // the default mode pauses while AppKit is mouse-tracking, which is
        // exactly when hover-driven expand/collapse happens, so `.default`
        // alone would silently freeze the animation on every hover.
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func stopLoop() {
        displayTimer?.invalidate()
        displayTimer = nil
        lastTickTime = nil
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt: CGFloat
        if let last = lastTickTime {
            // Clamp so a stall (e.g. window resize, spotlight, whatever)
            // can't inject one huge unstable integration step when ticking
            // resumes.
            dt = CGFloat(min(now - last, 1.0 / 30.0))
        } else {
            dt = CGFloat(1.0 / 120.0)
        }
        lastTickTime = now

        step(&width, dt: dt)
        step(&height, dt: dt)

        onUpdate(CGSize(width: width.value, height: height.value))

        if isSettled(width), isSettled(height) {
            width.value = width.target
            width.velocity = 0
            height.value = height.target
            height.velocity = 0
            onUpdate(CGSize(width: width.value, height: height.value))
            stopLoop()
            onSettle?()
        }
    }

    private func step(_ axis: inout Axis, dt: CGFloat) {
        let displacement = axis.value - axis.target
        let springForce = -physics.stiffness * displacement
        let dampingForce = -physics.damping * axis.velocity
        let acceleration = (springForce + dampingForce) / physics.mass
        axis.velocity += acceleration * dt
        axis.value += axis.velocity * dt
    }

    private func isSettled(_ axis: Axis) -> Bool {
        abs(axis.value - axis.target) < positionEpsilon && abs(axis.velocity) < velocityEpsilon
    }
}
