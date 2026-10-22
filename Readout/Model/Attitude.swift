import Foundation
import simd

/// Which way the phone is facing: the rotation that takes a direction in the phone's own frame
/// (x to the right of the screen, y to its top, z out of the glass) to the frame Core Motion
/// measures against, whose z axis points straight up (R-86).
///
/// Kept as a quaternion rather than as pitch, roll and yaw. Euler angles lock up — yaw stops
/// meaning anything — exactly when the phone is held upright, which is the pose the 3D view
/// is most often shown off in. On a phone the quaternion comes straight from `CMAttitude`;
/// only the Simulator, whose synthetic source has nothing but Euler angles, builds one from
/// them.
struct Attitude: Sendable, Equatable {
    /// The quaternion's components, stored rather than the `simd_quatd` itself so the type is
    /// plainly `Sendable`.
    let x: Double
    let y: Double
    let z: Double
    let w: Double

    static let identity = Attitude(x: 0, y: 0, z: 0, w: 1)

    private init(x: Double, y: Double, z: Double, w: Double) {
        self.x = x
        self.y = y
        self.z = z
        self.w = w
    }

    init(_ quaternion: simd_quatd) {
        let unit = simd_normalize(quaternion)
        x = unit.imag.x
        y = unit.imag.y
        z = unit.imag.z
        w = unit.real
    }

    var quaternion: simd_quatd { simd_quatd(ix: x, iy: y, iz: z, r: w) }

    /// A direction in the phone's frame, expressed in the reference frame.
    func rotate(_ vector: Vector3) -> Vector3 {
        Vector3(quaternion.act(vector.simd))
    }

    /// A direction in the reference frame, expressed in the phone's frame.
    func unrotate(_ vector: Vector3) -> Vector3 {
        Vector3(quaternion.inverse.act(vector.simd))
    }
}

extension Vector3 {
    var simd: SIMD3<Double> { SIMD3(x, y, z) }

    init(_ vector: SIMD3<Double>) {
        self.init(x: vector.x, y: vector.y, z: vector.z)
    }
}
