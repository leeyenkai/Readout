import CoreMotion
import Foundation

/// Acceleration, rotation rate, orientation and magnetic field, from the single
/// `CMMotionManager` Apple asks apps to share (R-63).
@MainActor
@Observable
final class MotionProvider: SensorProvider {
    let readings: Set<ReadingID> = [.acceleration, .rotationRate, .orientation, .magneticField]
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Acceleration hides gravity by default; the detail view can put it back (R-30).
    var includesGravity = false

    /// The gravity vector, which the spirit level works from directly (R-32).
    private(set) var gravity: Vector3?

    private let manager = CMMotionManager()
    private var active: Set<ReadingID> = []

    func isSupported(_ reading: ReadingID) -> Bool {
        switch reading {
        case .acceleration, .orientation: manager.isDeviceMotionAvailable
        case .rotationRate: manager.isGyroAvailable
        case .magneticField: manager.isMagnetometerAvailable
        default: false
        }
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard isSupported(reading) else { return }
        active.insert(reading)
        switch reading {
        case .acceleration, .orientation:
            manager.deviceMotionUpdateInterval = rate.interval
            startDeviceMotion()
        case .rotationRate:
            manager.gyroUpdateInterval = rate.interval
            startGyroscope()
        case .magneticField:
            manager.magnetometerUpdateInterval = rate.interval
            startMagnetometer()
        default:
            break
        }
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        switch reading {
        case .acceleration, .orientation:
            if active.isDisjoint(with: [.acceleration, .orientation]) {
                manager.stopDeviceMotionUpdates()
            }
        case .rotationRate:
            manager.stopGyroUpdates()
        case .magneticField:
            manager.stopMagnetometerUpdates()
        default:
            break
        }
    }

    // MARK: - Updates

    private func startDeviceMotion() {
        guard !manager.isDeviceMotionActive else { return }
        // `xTrueNorthZVertical` keeps yaw referenced to north where a magnetometer exists.
        let reference: CMAttitudeReferenceFrame = CMMotionManager.availableAttitudeReferenceFrames()
            .contains(.xTrueNorthZVertical) ? .xTrueNorthZVertical : .xArbitraryZVertical
        manager.startDeviceMotionUpdates(using: reference, to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            MainActor.assumeIsolated {
                self?.publish(motion)
            }
        }
    }

    private func startGyroscope() {
        guard !manager.isGyroActive else { return }
        manager.startGyroUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated {
                self?.output?(.rotationRate, SensorSample(values: [
                    data.rotationRate.x.degrees,
                    data.rotationRate.y.degrees,
                    data.rotationRate.z.degrees,
                ]))
            }
        }
    }

    private func startMagnetometer() {
        guard !manager.isMagnetometerActive else { return }
        manager.startMagnetometerUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated {
                self?.output?(.magneticField, SensorSample(values: [
                    data.magneticField.x,
                    data.magneticField.y,
                    data.magneticField.z,
                ]))
            }
        }
    }

    private func publish(_ motion: CMDeviceMotion) {
        gravity = Vector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z)
        if active.contains(.acceleration) {
            let user = motion.userAcceleration
            let gravity = motion.gravity
            let values = includesGravity
                ? [user.x + gravity.x, user.y + gravity.y, user.z + gravity.z]
                : [user.x, user.y, user.z]
            output?(.acceleration, SensorSample(
                values: values,
                note: includesGravity ? "Including gravity" : "Gravity removed"
            ))
        }
        if active.contains(.orientation) {
            output?(.orientation, SensorSample(values: [
                motion.attitude.pitch.degrees,
                motion.attitude.roll.degrees,
                motion.attitude.yaw.degrees,
            ]))
        }
    }

}

extension Double {
    /// Core Motion reports angles in radians; everything user-facing is in degrees.
    var degrees: Double { self * 180 / .pi }
}
