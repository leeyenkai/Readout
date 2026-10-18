import CoreMotion
import Foundation

/// Air pressure and the change in altitude since this reading started (R-6, R-7 in SPEC §3).
@MainActor
final class AltimeterProvider: SensorProvider {
    let readings: Set<ReadingID> = [.airPressure, .relativeAltitude]
    var output: ((ReadingID, SensorSample) -> Void)?

    private let altimeter = CMAltimeter()
    private var active: Set<ReadingID> = []

    func isSupported(_ reading: ReadingID) -> Bool {
        CMAltimeter.isRelativeAltitudeAvailable()
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard isSupported(reading) else { return }
        let wasIdle = active.isEmpty
        active.insert(reading)
        guard wasIdle else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let data else { return }
            MainActor.assumeIsolated {
                self?.publish(data)
            }
        }
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        if active.isEmpty {
            altimeter.stopRelativeAltitudeUpdates()
        }
    }

    private func publish(_ data: CMAltitudeData) {
        if active.contains(.airPressure) {
            // Core Motion reports kilopascal; the spec shows hectopascal.
            output?(.airPressure, SensorSample(values: [data.pressure.doubleValue * 10]))
        }
        if active.contains(.relativeAltitude) {
            output?(.relativeAltitude, SensorSample(
                values: [data.relativeAltitude.doubleValue],
                note: "Since this reading started"
            ))
        }
    }
}
