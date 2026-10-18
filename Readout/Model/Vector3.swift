import Foundation

/// A three-component vector in the phone's own frame of reference.
struct Vector3: Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double { sqrt(x * x + y * y + z * z) }
}

/// The geometry behind the spirit level, kept pure so it is covered by tests (R-32).
enum LevelMaths {
    /// Whether the phone is lying flat enough to use the bubble, rather than standing on an
    /// edge. Gravity points almost entirely through the screen when the phone is flat.
    static func isSurfaceMode(gravity: Vector3) -> Bool {
        abs(gravity.z) > 0.7
    }

    /// Tilt of a flat phone along its own x and y axes, in degrees.
    static func surfaceAngles(gravity: Vector3) -> (x: Double, y: Double) {
        let down = gravity.z < 0 ? -gravity.z : gravity.z
        return (
            x: atan2(gravity.x, max(down, 0.0001)).degrees,
            y: atan2(gravity.y, max(down, 0.0001)).degrees
        )
    }

    /// How far a phone standing on an edge is from plumb, in degrees. Zero means upright.
    static func edgeAngle(gravity: Vector3) -> Double {
        atan2(gravity.x, -gravity.y).degrees
    }

    /// Rebuilds a gravity vector from pitch and roll, for sources that report an attitude
    /// but no gravity of their own.
    static func gravity(pitchDegrees: Double, rollDegrees: Double) -> Vector3 {
        let pitch = pitchDegrees * .pi / 180
        let roll = rollDegrees * .pi / 180
        return Vector3(
            x: -sin(roll) * cos(pitch),
            y: -sin(pitch),
            z: -cos(roll) * cos(pitch)
        )
    }

    /// Total tilt of a flat phone from horizontal, in degrees.
    static func surfaceTilt(gravity: Vector3) -> Double {
        let clamped = min(max(abs(gravity.z) / max(gravity.magnitude, 0.0001), 0), 1)
        return acos(clamped).degrees
    }
}
