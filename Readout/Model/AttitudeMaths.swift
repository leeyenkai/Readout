import Foundation
import simd

/// The geometry behind the 3D phone, kept pure so it is covered by tests (R-86).
///
/// Three frames are involved. The phone's own: x to the right of the screen, y to its top, z
/// out of the glass. Core Motion's reference frame: z straight up, x and y level. And the
/// scene the model is drawn in, which follows RealityKit: y up, and +z towards whoever is
/// looking at the screen.
enum AttitudeMaths {
    /// Standard gravity, for turning Core Motion's g into metres per second squared.
    static let standardGravity = 9.806_65

    /// The reference frame turned into the scene's: up stays up, and the reference frame's +y
    /// becomes the scene's −z, "away from the viewer". A quarter turn about x.
    static var referenceToScene: simd_quatd { simd_quatd(angle: -.pi / 2, axis: SIMD3(1, 0, 0)) }

    /// The attitude Core Motion would report for these Euler angles, in degrees.
    ///
    /// Only the Simulator needs this: a phone hands over its quaternion directly. Core Motion
    /// composes yaw about z, then pitch about x, then roll about y — R = Rz(yaw)·Rx(pitch)·
    /// Ry(roll) — which is why pitch, the middle angle, is the one confined to ±90°.
    static func attitude(pitchDegrees: Double, rollDegrees: Double, yawDegrees: Double) -> Attitude {
        let pitch = simd_quatd(angle: radians(pitchDegrees), axis: SIMD3(1, 0, 0))
        let roll = simd_quatd(angle: radians(rollDegrees), axis: SIMD3(0, 1, 0))
        let yaw = simd_quatd(angle: radians(yawDegrees), axis: SIMD3(0, 0, 1))
        return Attitude(yaw * pitch * roll)
    }

    /// Gravity in the phone's own frame, in g — the vector Core Motion reports as
    /// `CMDeviceMotion.gravity`. A phone lying flat reads (0, 0, −1).
    static func gravity(_ attitude: Attitude) -> Vector3 {
        attitude.unrotate(Vector3(x: 0, y: 0, z: -1))
    }

    // MARK: - Recentring

    /// The turn about the vertical that puts the side of the phone facing away from the user
    /// at the back of the scene, so the model starts out the way the real phone is held.
    ///
    /// "Away from the user" is the back of the phone wherever the screen is anywhere near
    /// upright, because the user is looking at the screen; for a phone lying flat, whose back
    /// faces the floor, it is the top edge instead. Euler yaw cannot be used: it is undefined
    /// for a phone held upright, the commonest pose of all. Nil when neither direction is
    /// level enough to say — the caller keeps whatever it had.
    static func recentringYaw(_ attitude: Attitude) -> Double? {
        let back = horizontal(attitude.rotate(Vector3(x: 0, y: 0, z: -1)))
        let top = horizontal(attitude.rotate(Vector3(x: 0, y: 1, z: 0)))
        let away = simd_length(back) >= 0.3 ? back : top
        guard simd_length(away) >= 0.3 else { return nil }
        // Turn `away` onto the reference frame's +y, which the scene draws as "into the screen".
        return .pi / 2 - atan2(away.y, away.x)
    }

    /// How the model is turned in the scene: the phone's attitude, turned about the vertical
    /// by the recentring yaw, then expressed in the scene's axes. The model is built in the
    /// phone's own axes, so this is all it needs.
    static func sceneOrientation(_ attitude: Attitude, yaw: Double) -> simd_quatd {
        let turn = simd_quatd(angle: yaw, axis: SIMD3(0, 0, 1))
        return referenceToScene * turn * attitude.quaternion
    }

    /// The acceleration the user is giving the phone, in metres per second squared, in the
    /// scene's axes.
    ///
    /// Core Motion reports acceleration the way gravity reads — a phone at rest on a table
    /// reads −1 g on z, and one in free fall reads nothing — so its `userAcceleration` points
    /// the opposite way to the push. It is negated here, so a phone pushed to the right
    /// drives the model to the right.
    static func sceneAcceleration(_ userAcceleration: Vector3, attitude: Attitude, yaw: Double) -> SIMD3<Double> {
        let orientation = sceneOrientation(attitude, yaw: yaw)
        return -standardGravity * orientation.act(userAcceleration.simd)
    }

    private static func horizontal(_ vector: Vector3) -> SIMD2<Double> {
        SIMD2(vector.x, vector.y)
    }

    private static func radians(_ degrees: Double) -> Double {
        degrees * .pi / 180
    }
}
