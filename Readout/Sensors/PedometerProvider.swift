import CoreMotion
import Foundation

/// Today's step totals, plus live cadence and pace while walking (R-70).
@MainActor
final class PedometerProvider: SensorProvider {
    let readings: Set<ReadingID> = [.activity, .cadence]
    var output: ((ReadingID, SensorSample) -> Void)?

    private let pedometer = CMPedometer()
    private var active: Set<ReadingID> = []
    private var isStreaming = false

    func isSupported(_ reading: ReadingID) -> Bool {
        switch reading {
        case .activity: CMPedometer.isStepCountingAvailable()
        case .cadence: CMPedometer.isPaceAvailable() || CMPedometer.isCadenceAvailable()
        default: false
        }
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard isSupported(reading) else { return }
        active.insert(reading)
        if reading == .activity {
            queryToday()
        }
        startStreaming()
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        if active.isEmpty, isStreaming {
            pedometer.stopUpdates()
            isStreaming = false
        }
    }

    /// Today's totals come from the motion coprocessor's own log, not from live counting.
    private func queryToday() {
        let startOfDay = Calendar.current.startOfDay(for: .now)
        pedometer.queryPedometerData(from: startOfDay, to: .now) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                self?.publishTotals(data)
            }
        }
    }

    private func startStreaming() {
        guard !isStreaming else { return }
        isStreaming = true
        let startOfDay = Calendar.current.startOfDay(for: .now)
        pedometer.startUpdates(from: startOfDay) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                publishTotals(data)
                publishLive(data)
            }
        }
    }

    private func publishTotals(_ data: CMPedometerData) {
        guard active.contains(.activity) else { return }
        output?(.activity, SensorSample(values: [
            data.numberOfSteps.doubleValue,
            data.distance?.doubleValue ?? 0,
            data.floorsAscended?.doubleValue ?? 0,
        ]))
    }

    private func publishLive(_ data: CMPedometerData) {
        guard active.contains(.cadence) else { return }
        // Core Motion gives cadence in steps per second and pace in seconds per metre.
        let cadence = (data.currentCadence?.doubleValue ?? 0) * 60
        let pacePerKilometre = (data.currentPace?.doubleValue ?? 0) * 1_000
        output?(.cadence, SensorSample(
            values: [cadence, pacePerKilometre],
            note: cadence > 0 ? nil : "Start walking"
        ))
    }
}
