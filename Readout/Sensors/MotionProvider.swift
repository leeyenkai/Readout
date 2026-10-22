import CoreMotion
import Foundation
import simd

/// Acceleration, rotation rate, orientation and magnetic field, from the single
/// `CMMotionManager` Apple asks apps to share (R-63).
@MainActor
@Observable
final class MotionProvider: SensorProvider {
    let readings: Set<ReadingID> = [.acceleration, .rotationRate, .orientation, .magneticField]
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Acceleration hides gravity by default; the detail view can put it back (R-30).
    var includesGravity = false

    /// Whether Location is allowed, which decides whether yaw can be measured from true north.
    /// Set by `SensorHub`.
    var isLocationAuthorized = false

    /// The gravity vector, which the spirit level works from directly (R-32).
    private(set) var gravity: Vector3?
    /// The phone's attitude as a quaternion, for the 3D view (R-86). Pitch, roll and yaw are
    /// what the Orientation reading shows, but they cannot describe a phone held upright.
    private(set) var attitude: Attitude?
    /// Acceleration with gravity taken out, in g, whatever the Include gravity setting says:
    /// the 3D view's sway wants the push alone (R-86).
    private(set) var userAcceleration: Vector3?

    private let manager = CMMotionManager()
    private var active: Set<ReadingID> = []
    /// The rate each running reading asked for. Acceleration and orientation share Core
    /// Motion's one device-motion stream, so it runs at the faster of the two.
    private var rates: [ReadingID: ActivationRate] = [:]
    /// Set once true north has been refused, so the stream is not asked for it again until
    /// device motion next starts from scratch.
    private var isTrueNorthUnavailable = false

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
        rates[reading] = rate
        switch reading {
        case .acceleration, .orientation:
            // Setting the interval on every start, as this used to, let whichever reading
            // started last decide for both: a 50 Hz recording of acceleration dropped to
            // 10 Hz when the grid took its lease on orientation.
            if let interval = Self.deviceMotionInterval(for: rates) {
                manager.deviceMotionUpdateInterval = interval
            }
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
        rates[reading] = nil
        switch reading {
        case .acceleration, .orientation:
            if let interval = Self.deviceMotionInterval(for: rates) {
                manager.deviceMotionUpdateInterval = interval
            } else {
                manager.stopDeviceMotionUpdates()
                isTrueNorthUnavailable = false
                // Nothing here is true any more. A spirit level opened later would otherwise
                // show the last tilt it saw until the first new value arrived (P-2).
                gravity = nil
                attitude = nil
                userAcceleration = nil
            }
        case .rotationRate:
            manager.stopGyroUpdates()
        case .magneticField:
            manager.stopMagnetometerUpdates()
        default:
            break
        }
    }

    /// The device-motion update interval for these leases: the shortest any of the readings
    /// sharing that stream asked for, or nil when neither is running.
    nonisolated static func deviceMotionInterval(for rates: [ReadingID: ActivationRate]) -> TimeInterval? {
        [ReadingID.acceleration, .orientation]
            .compactMap { rates[$0] }
            .max()
            .map(\.interval)
    }

    // MARK: - Updates

    /// True north where Location allows it, so yaw means something; magnetic north where it
    /// does not; an arbitrary but magnetometer-steadied heading on a phone with neither.
    ///
    /// True north needs a location. Asked for without one, Core Motion reports
    /// `CMErrorTrueNorthNotAvailable` and no motion at all — which, unhandled, left
    /// acceleration, orientation and the spirit level waiting for ever on a phone that had
    /// refused Location, for want of a heading none of them use.
    private var referenceFrame: CMAttitudeReferenceFrame {
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        if isLocationAuthorized, !isTrueNorthUnavailable, available.contains(.xTrueNorthZVertical) {
            return .xTrueNorthZVertical
        }
        if available.contains(.xMagneticNorthZVertical) { return .xMagneticNorthZVertical }
        if available.contains(.xArbitraryCorrectedZVertical) { return .xArbitraryCorrectedZVertical }
        return .xArbitraryZVertical
    }

    private func startDeviceMotion() {
        guard !manager.isDeviceMotionActive else { return }
        let reference = referenceFrame
        manager.startDeviceMotionUpdates(using: reference, to: .main) { [weak self] motion, error in
            let refusedTrueNorth = (error as NSError?).map {
                $0.domain == CMErrorDomain && $0.code == Int(CMErrorTrueNorthNotAvailable.rawValue)
            } ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                if let motion {
                    self.publish(motion)
                } else if refusedTrueNorth, reference == .xTrueNorthZVertical {
                    self.fallBackFromTrueNorth()
                }
            }
        }
    }

    /// Restarts the stream against magnetic north after true north was refused.
    private func fallBackFromTrueNorth() {
        isTrueNorthUnavailable = true
        manager.stopDeviceMotionUpdates()
        guard !active.isDisjoint(with: [.acceleration, .orientation]) else { return }
        startDeviceMotion()
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
        let user = motion.userAcceleration
        let gravity = motion.gravity
        let quaternion = motion.attitude.quaternion
        self.gravity = Vector3(x: gravity.x, y: gravity.y, z: gravity.z)
        attitude = Attitude(simd_quatd(ix: quaternion.x, iy: quaternion.y, iz: quaternion.z, r: quaternion.w))
        userAcceleration = Vector3(x: user.x, y: user.y, z: user.z)
        if active.contains(.acceleration) {
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
