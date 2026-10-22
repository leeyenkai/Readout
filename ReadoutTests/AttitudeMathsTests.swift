import Foundation
import simd
import Testing
@testable import Readout

/// The geometry behind the 3D phone (R-86): which way the model faces for a given attitude,
/// and that it moves the way the phone does rather than as its mirror image.
@Suite("Attitude maths")
struct AttitudeMathsTests {
    /// Where one of the phone's own directions ends up in the scene.
    private func scene(_ direction: SIMD3<Double>, pitch: Double, roll: Double, yaw: Double, recentred: Bool = true) -> SIMD3<Double> {
        let attitude = AttitudeMaths.attitude(pitchDegrees: pitch, rollDegrees: roll, yawDegrees: yaw)
        let turn = recentred ? (AttitudeMaths.recentringYaw(attitude) ?? 0) : 0
        return AttitudeMaths.sceneOrientation(attitude, yaw: turn).act(direction)
    }

    private let screen = SIMD3<Double>(0, 0, 1)
    private let top = SIMD3<Double>(0, 1, 0)
    private let right = SIMD3<Double>(1, 0, 0)

    private func close(_ a: SIMD3<Double>, _ b: SIMD3<Double>, within tolerance: Double = 0.001) -> Bool {
        simd_length(a - b) < tolerance
    }

    @Test("Lying flat, the screen faces up and the top points away", arguments: [0.0, 73, -140])
    func flat(yaw: Double) {
        #expect(close(scene(screen, pitch: 0, roll: 0, yaw: yaw), SIMD3(0, 1, 0)))
        #expect(close(scene(top, pitch: 0, roll: 0, yaw: yaw), SIMD3(0, 0, -1)))
    }

    @Test("Held upright, the screen faces the viewer whichever way the user is facing", arguments: [0.0, 90, -120])
    func upright(yaw: Double) {
        #expect(close(scene(screen, pitch: 90, roll: 0, yaw: yaw), SIMD3(0, 0, 1)))
        #expect(close(scene(top, pitch: 90, roll: 0, yaw: yaw), SIMD3(0, 1, 0)))
    }

    /// The model is the phone, not its reflection: turning to the right turns it to the right.
    @Test("Turning the phone to the right turns the model to the right")
    func turningRight() {
        let held = AttitudeMaths.attitude(pitchDegrees: 90, rollDegrees: 0, yawDegrees: 0)
        let turn = AttitudeMaths.recentringYaw(held) ?? 0
        // 30° clockwise seen from above is −30° about the vertical.
        let turned = AttitudeMaths.attitude(pitchDegrees: 90, rollDegrees: 0, yawDegrees: -30)
        let orientation = AttitudeMaths.sceneOrientation(turned, yaw: turn)
        // Turning clockwise seen from above brings the right edge round towards the viewer,
        // and the screen, which was facing them, turns to face their left.
        #expect(orientation.act(right).z > 0.4)
        #expect(orientation.act(screen).x < -0.4)
    }

    @Test("Rolling a flat phone lowers its right edge, and pitching it raises its top")
    func tilting() {
        #expect(scene(right, pitch: 0, roll: 20, yaw: 0).y < -0.3)
        #expect(scene(top, pitch: 20, roll: 0, yaw: 0).y > 0.3)
    }

    @Test("Gravity follows the right-hand rule: positive roll lowers the right edge")
    func gravityFromAngles() {
        let pitch = 12.0, roll = 25.0
        let gravity = AttitudeMaths.gravity(AttitudeMaths.attitude(pitchDegrees: pitch, rollDegrees: roll, yawDegrees: 40))
        let p = pitch * .pi / 180, r = roll * .pi / 180
        #expect(abs(gravity.x - sin(r) * cos(p)) < 0.000_1)
        #expect(abs(gravity.y - -sin(p)) < 0.000_1)
        #expect(abs(gravity.z - -cos(r) * cos(p)) < 0.000_1)
        #expect(gravity.x > 0)
        // And the spirit level's own reconstruction agrees, so the two never disagree.
        let level = LevelMaths.gravity(pitchDegrees: pitch, rollDegrees: roll)
        #expect(abs(level.x - gravity.x) < 0.000_1 && abs(level.y - gravity.y) < 0.000_1)
    }

    /// Euler yaw is undefined when the phone is upright; the recentring must not be.
    @Test("Raising the phone from flat to upright tips the model straight towards the viewer")
    func recentringIsStable() {
        for pitch in stride(from: 0.0, through: 90, by: 5) {
            let top = scene(self.top, pitch: pitch, roll: 0, yaw: 57)
            let screen = scene(self.screen, pitch: pitch, roll: 0, yaw: 57)
            #expect(abs(top.x) < 0.001)
            #expect(abs(screen.x) < 0.001)
            #expect(screen.z > -0.001)
        }
    }

    /// The back and the top are at right angles, so at least one of them is always level
    /// enough to say which way is "away".
    @Test("Every pose has a direction to recentre on")
    func everyPoseRecentres() {
        for pitch in stride(from: -90.0, through: 90, by: 30) {
            for roll in stride(from: -180.0, through: 180, by: 45) {
                let attitude = AttitudeMaths.attitude(pitchDegrees: pitch, rollDegrees: roll, yawDegrees: 20)
                #expect(AttitudeMaths.recentringYaw(attitude) != nil)
            }
        }
    }

    /// Core Motion's user acceleration points against the push, the way gravity reads.
    @Test("A push to the right drives the model to the right")
    func pushDirection() {
        let flat = AttitudeMaths.attitude(pitchDegrees: 0, rollDegrees: 0, yawDegrees: 0)
        let push = AttitudeMaths.sceneAcceleration(Vector3(x: -0.102, y: 0, z: 0), attitude: flat, yaw: 0)
        #expect(abs(push.x - 1) < 0.01)
        #expect(abs(push.y) < 0.001 && abs(push.z) < 0.001)
    }

    @Test("The device-motion stream runs at the faster of the two readings that share it")
    func sharedMotionRate() {
        #expect(MotionProvider.deviceMotionInterval(for: [:]) == nil)
        #expect(MotionProvider.deviceMotionInterval(for: [.magneticField: .display]) == nil)
        let both: [ReadingID: ActivationRate] = [.acceleration: .fast, .orientation: .standard]
        #expect(MotionProvider.deviceMotionInterval(for: both) == ActivationRate.fast.interval)
        let display: [ReadingID: ActivationRate] = [.acceleration: .standard, .orientation: .display]
        #expect(MotionProvider.deviceMotionInterval(for: display) == ActivationRate.display.interval)
    }
}

@Suite("Inertial spring")
struct InertialSpringTests {
    private func run(_ spring: inout InertialSpring, drive: SIMD3<Double>, seconds: Double, frame: Double = 1.0 / 60) {
        var elapsed = 0.0
        while elapsed < seconds - 1e-9 {
            spring.step(drive: drive, deltaTime: frame)
            elapsed += frame
        }
    }

    @Test("At rest it stays at rest")
    func rest() {
        var spring = InertialSpring()
        run(&spring, drive: .zero, seconds: 2)
        #expect(spring.position == .zero)
    }

    /// The whole reason for a spring: a bias that would integrate to metres holds it a
    /// millimetre or two off centre.
    @Test("A steady bias barely moves it")
    func biasIsHarmless() {
        var spring = InertialSpring()
        run(&spring, drive: SIMD3(0.02 * AttitudeMaths.standardGravity, 0, 0), seconds: 10)
        #expect(abs(spring.position.x) < 0.002)
    }

    @Test("Noise under the dead zone does nothing at all")
    func deadZone() {
        var spring = InertialSpring()
        run(&spring, drive: SIMD3(0.1, -0.05, 0.08), seconds: 2)
        #expect(spring.position == .zero)
    }

    @Test("A push moves it the same way, then it settles back")
    func pushAndSettle() {
        var spring = InertialSpring()
        run(&spring, drive: SIMD3(3, 0, 0), seconds: 0.2)
        #expect(spring.position.x > 0)
        run(&spring, drive: .zero, seconds: 3)
        #expect(simd_length(spring.position) < 0.000_1)
    }

    @Test("It moves the same at 30, 60 and 120 frames a second")
    func frameRateIndependent() {
        var slow = InertialSpring(), medium = InertialSpring(), fast = InertialSpring()
        let drive = SIMD3<Double>(2, -1, 0.5)
        run(&slow, drive: drive, seconds: 1, frame: 1.0 / 30)
        run(&medium, drive: drive, seconds: 1, frame: 1.0 / 60)
        run(&fast, drive: drive, seconds: 1, frame: 1.0 / 120)
        #expect(simd_length(slow.position - fast.position) < 0.001)
        #expect(simd_length(medium.position - fast.position) < 0.001)
    }

    @Test("A violent shake never takes it past its limit")
    func clamped() {
        var spring = InertialSpring()
        run(&spring, drive: SIMD3(50, 50, 50), seconds: 1)
        #expect(simd_length(spring.position) <= InertialSpring.Parameters.sway.maximumOffset + 1e-9)
    }

    @Test("A stall or a bad sample does not fling it")
    func badInput() {
        var spring = InertialSpring()
        spring.step(drive: SIMD3(.nan, 0, 0), deltaTime: 1.0 / 60)
        spring.step(drive: SIMD3(3, 0, 0), deltaTime: 5)
        spring.step(drive: .zero, deltaTime: .nan)
        #expect(spring.position.x.isFinite)
        #expect(simd_length(spring.position) <= InertialSpring.Parameters.sway.maximumOffset + 1e-9)
    }
}
