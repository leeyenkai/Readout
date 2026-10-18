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

    private var active: Set<ReadingID> = []
    private var timer: Timer?
    private var phase: Double = 0
    private let startedAt = Date.now

    func isSupported(_ reading: ReadingID) -> Bool { true }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        active.insert(reading)
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
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
    }

    private func tick() {
        phase += 1.0 / 20
        for reading in active {
            output?(reading, sample(for: reading))
        }
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
            return SensorSample(values: [slow * 0.2 + noise, medium * 0.2 + noise, fast * 0.1 - 1 + noise], note: note)
        case .rotationRate:
            return SensorSample(values: [slow * 40, medium * 25, fast * 60], note: note)
        case .orientation:
            return SensorSample(values: [slow * 20, medium * 15, (phase * 8).truncatingRemainder(dividingBy: 360) - 180], note: note)
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
