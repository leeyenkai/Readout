import Foundation
import simd

/// A damped spring driven by acceleration, which is how the 3D phone shows a push without
/// pretending to know where the phone is (R-86, P-2).
///
/// Integrating acceleration twice to get a position is what an app would do if it wanted to
/// claim it was tracking the phone through space, and it does not work: a bias of a fiftieth
/// of a g — ordinary for a phone's accelerometer — integrates to about ten metres of
/// imaginary travel in ten seconds. A spring instead turns the same signal into a sway that
/// moves the way the phone was moved and always settles back: the same bias holds it about a
/// millimetre off centre.
///
/// `x'' = gain·a − stiffness·x − damping·x'`, stepped with semi-implicit Euler in fixed
/// sub-steps so the motion is the same at 60 and 120 frames a second.
struct InertialSpring: Sendable, Equatable {
    struct Parameters: Sendable, Equatable {
        /// Pull back towards the centre, per metre, per second squared.
        var stiffness: Double
        /// Resistance to moving, per metre per second.
        var damping: Double
        /// How much of the acceleration drives the spring.
        var gain: Double
        /// The furthest the spring may stretch, in metres.
        var maximumOffset: Double
        /// Acceleration below this, in metres per second squared, is treated as sensor noise.
        var deadZone: Double

        /// The phone's sway: about 1.2 Hz, a little under-damped so a push ends with a small
        /// swing back, settling in about a second. A third of a hand's jerk comes through, so
        /// the model moves with the phone without leaving the stage.
        static let sway = Parameters(
            stiffness: 56.25,
            damping: 8.25,
            gain: 0.3,
            maximumOffset: 0.03,
            deadZone: 0.15
        )
    }

    let parameters: Parameters
    private(set) var position: SIMD3<Double> = .zero
    private(set) var velocity: SIMD3<Double> = .zero

    /// Fixed integration step. Small enough to stay stable at this stiffness, and the same
    /// whatever the display's frame rate.
    private static let integrationStep: Double = 1.0 / 240
    /// A frame longer than this — a hitch, the app coming back from the background — is not
    /// integrated in full, or one stall would fling the model across the stage.
    private static let longestFrame: Double = 0.1

    init(parameters: Parameters = .sway) {
        self.parameters = parameters
    }

    mutating func step(drive acceleration: SIMD3<Double>, deltaTime: Double) {
        guard deltaTime.isFinite, deltaTime > 0 else { return }
        let drive = Self.isFinite(acceleration) ? deadZoned(acceleration) : .zero
        var remaining = min(deltaTime, Self.longestFrame)
        while remaining > 1e-9 {
            let h = min(Self.integrationStep, remaining)
            let force = parameters.gain * drive - parameters.stiffness * position - parameters.damping * velocity
            velocity += h * force
            position += h * velocity
            clamp()
            remaining -= h
        }
    }

    mutating func reset() {
        position = .zero
        velocity = .zero
    }

    /// Shrinks the drive by the dead zone along its own direction, so a reading just above the
    /// threshold starts the sway gently rather than with a jump.
    private func deadZoned(_ acceleration: SIMD3<Double>) -> SIMD3<Double> {
        let magnitude = simd_length(acceleration)
        guard magnitude > parameters.deadZone, magnitude > 0 else { return .zero }
        return acceleration * ((magnitude - parameters.deadZone) / magnitude)
    }

    /// Holds the stretch inside a sphere rather than a box — a diagonal push is not allowed
    /// further than a straight one — and stops the spring pushing outwards against the wall.
    private mutating func clamp() {
        let length = simd_length(position)
        guard length > parameters.maximumOffset, length > 0 else { return }
        let direction = position / length
        position = direction * parameters.maximumOffset
        let outward = simd_dot(velocity, direction)
        if outward > 0 {
            velocity -= outward * direction
        }
    }

    private static func isFinite(_ vector: SIMD3<Double>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }
}
