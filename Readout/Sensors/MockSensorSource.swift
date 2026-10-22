import Foundation

/// Stands in for the hardware the Simulator does not have, so the whole interface can be run
/// and previewed without a device (R-71).
///
/// It is only ever used in the Simulator and in previews. On a real iPhone a reading the
/// device lacks is hidden instead (R-7).
@MainActor
final class MockSensorSource: SensorProvider {
    let readings: Set<ReadingID> = Set(ReadingID.allCases)
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Mirrors the Include gravity setting, as the real motion provider does (R-30).
    var includesGravity = false

    private var active: Set<ReadingID> = []
    private var timer: Timer?
    private var interval: TimeInterval = 0
    private var phase: Double = 0
    private var lastSlowTick = Date.distantPast
    private let startedAt = Date.now

    func isSupported(_ reading: ReadingID) -> Bool { true }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        active.insert(reading)
        // A recording asking for 50 Hz gets 50 Hz of synthetic data, so the rates can be
        // told apart in the Simulator (R-39, R-71).
        let wanted = min(rate.interval, 1.0 / 20)
        guard timer == nil || wanted < interval else { return }
        timer?.invalidate()
        interval = wanted
        let timer = Timer(timeInterval: wanted, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        guard active.isEmpty else { return }
        timer?.invalidate()
        timer = nil
        interval = 0
    }

    private func tick() {
        phase += interval
        // Core Location, the altimeter and the pedometer report about once a second however
        // fast an app asks; the mock does the same, so a recording made in the Simulator has
        // the shape one made on a phone would (R-39, R-71).
        let isSlowDue = Date.now.timeIntervalSince(lastSlowTick) >= 1
        if isSlowDue { lastSlowTick = .now }
        for reading in active {
            guard ReadingCatalog.descriptor(reading).recordingCadence != .free || isSlowDue else { continue }
            output?(reading, sample(for: reading))
        }
    }

    /// Held up at a comfortable reading angle and drifting about it, the way a phone in a hand
    /// does, rather than a value that only ever ramps.
    private var pitch: Double { 35 + 25 * sin(phase * 0.5) }
    private var roll: Double { 20 * sin(phase * 0.73) }
    private var yaw: Double { 50 * sin(phase * 0.21) }

    /// One push-and-stop every `period` seconds: a single sine cycle lasting 0.8 s, so the
    /// phone speeds up and then slows back down to rest.
    private func push(period: Double, offset: Double) -> Double {
        let time = (phase + offset).truncatingRemainder(dividingBy: period)
        guard time < 0.8 else { return 0 }
        return sin(time / 0.8 * 2 * .pi)
    }

    /// Plausible-looking but obviously synthetic values: slow sine waves with a little noise.
    private func sample(for reading: ReadingID) -> SensorSample {
        let slow = sin(phase * 0.6)
        let medium = sin(phase * 1.7)
        let fast = sin(phase * 3.1)
        let noise = Double.random(in: -0.02...0.02)
        let note = "Simulated"

        switch reading {
        case .acceleration:
            // A phone held in the hand: still most of the time, with a push and a stop every
            // few seconds, so the 3D view's sway has something to show (R-86).
            // Less noise than the other readings: a still phone's accelerometer is quiet, and
            // more would keep the sway twitching.
            let jitter = noise * 0.25
            var user = Vector3(
                x: push(period: 6, offset: 0) * 0.25 + jitter,
                y: push(period: 6, offset: 3) * 0.2 + jitter,
                z: medium * 0.02 + jitter
            )
            if includesGravity {
                let gravity = LevelMaths.gravity(pitchDegrees: pitch, rollDegrees: roll)
                user = Vector3(x: user.x + gravity.x, y: user.y + gravity.y, z: user.z + gravity.z)
            }
            return SensorSample(values: [user.x, user.y, user.z], note: note)
        case .rotationRate:
            // The rates the orientation below is actually turning at, so the two agree.
            return SensorSample(values: [
                25 * 0.5 * cos(phase * 0.5),
                20 * 0.73 * cos(phase * 0.73),
                50 * 0.21 * cos(phase * 0.21),
            ], note: note)
        case .orientation:
            return SensorSample(values: [pitch, roll, yaw], note: note)
        case .magneticField:
            return SensorSample(values: [22 + slow * 4, -14 + medium * 4, 38 + fast * 3], note: note)
        case .heading:
            return SensorSample(values: [(phase * 6).truncatingRemainder(dividingBy: 360)], note: note)
        case .airPressure:
            return SensorSample(values: [1_013.2 + slow * 1.5], note: note)
        case .relativeAltitude:
            return SensorSample(values: [slow * 4], note: note)
        case .soundLevel:
            return SensorSample(values: [48 + medium * 12 + Double.random(in: -2...2)], note: note)
        case .light:
            return SensorSample(values: [320 + fast * 180 + Double.random(in: -20...20)], note: note)
        case .coordinates:
            return SensorSample(values: [1.3521 + slow * 0.0004, 103.8198 + medium * 0.0004], note: note)
        case .gpsAltitude:
            return SensorSample(values: [24 + slow * 3], note: note)
        case .speed:
            return SensorSample(values: [max(0, 1.4 + medium * 1.2)], note: note)
        case .course:
            return SensorSample(values: [(phase * 4 + 90).truncatingRemainder(dividingBy: 360)], note: note)
        case .locationAccuracy:
            return SensorSample(values: [6 + abs(slow) * 8, 9 + abs(medium) * 10], note: note)
        case .activity:
            let elapsed = Date.now.timeIntervalSince(startedAt)
            return SensorSample(values: [(4_280 + elapsed * 2).rounded(), 3_120 + elapsed * 1.4, 7], note: note)
        case .cadence:
            return SensorSample(values: [112 + medium * 8, 560 + slow * 40], note: note)
        case .proximity:
            let isNear = sin(phase * 0.4) > 0.5
            return SensorSample(values: [isNear ? 1 : 0], state: isNear ? "Near" : "Far", note: note)
        case .battery:
            return SensorSample(values: [72], state: nil, note: "Simulated · Charging")
        case .thermalState:
            return SensorSample(values: [0], state: "Nominal", note: "Simulated · Running cool")
        }
    }
}
