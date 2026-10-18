import UIKit

/// Battery, proximity and thermal state — reported by iOS rather than measured (SPEC §3).
@MainActor
final class DeviceProvider: SensorProvider {
    let readings: Set<ReadingID> = [.battery, .proximity, .thermalState]
    var output: ((ReadingID, SensorSample) -> Void)?

    private var active: Set<ReadingID> = []
    private var observers: [ReadingID: [NSObjectProtocol]] = [:]

    func isSupported(_ reading: ReadingID) -> Bool {
        switch reading {
        case .proximity:
            // Asking is the only way to find out, so enable briefly and see if iOS agrees.
            let device = UIDevice.current
            guard !device.isProximityMonitoringEnabled else { return true }
            device.isProximityMonitoringEnabled = true
            let supported = device.isProximityMonitoringEnabled
            device.isProximityMonitoringEnabled = false
            return supported
        default:
            return true
        }
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard !active.contains(reading) else { return }
        active.insert(reading)
        switch reading {
        case .battery:
            UIDevice.current.isBatteryMonitoringEnabled = true
            observe(reading, names: [
                UIDevice.batteryLevelDidChangeNotification,
                UIDevice.batteryStateDidChangeNotification,
            ]) { [weak self] in self?.publishBattery() }
            publishBattery()
        case .proximity:
            // Monitoring blanks the screen when covered, so it only ever runs on request (R-68).
            UIDevice.current.isProximityMonitoringEnabled = true
            observe(reading, names: [UIDevice.proximityStateDidChangeNotification]) { [weak self] in
                self?.publishProximity()
            }
            publishProximity()
        case .thermalState:
            observe(reading, names: [ProcessInfo.thermalStateDidChangeNotification]) { [weak self] in
                self?.publishThermalState()
            }
            publishThermalState()
        default:
            break
        }
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        observers[reading]?.forEach(NotificationCenter.default.removeObserver)
        observers[reading] = nil
        switch reading {
        case .battery: UIDevice.current.isBatteryMonitoringEnabled = false
        case .proximity: UIDevice.current.isProximityMonitoringEnabled = false
        default: break
        }
    }

    private func observe(_ reading: ReadingID, names: [Notification.Name], handler: @escaping @MainActor () -> Void) {
        let tokens = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated(handler)
            }
        }
        observers[reading, default: []].append(contentsOf: tokens)
    }

    private func publishBattery() {
        let device = UIDevice.current
        let level = device.batteryLevel
        let note: String? = switch device.batteryState {
        case .charging: "Charging"
        case .full: "Full"
        case .unplugged: nil
        case .unknown: "State unknown"
        @unknown default: nil
        }
        output?(.battery, SensorSample(values: [level < 0 ? 0 : Double(level) * 100], note: note))
    }

    private func publishProximity() {
        let isNear = UIDevice.current.proximityState
        output?(.proximity, SensorSample(values: [isNear ? 1 : 0], state: isNear ? "Near" : "Far"))
    }

    private func publishThermalState() {
        let state = ProcessInfo.processInfo.thermalState
        let label: String
        let note: String?
        switch state {
        case .nominal: label = "Nominal"; note = "Running cool"
        case .fair: label = "Fair"; note = "Warming up"
        case .serious: label = "Serious"; note = "iOS is throttling performance"
        case .critical: label = "Critical"; note = "The phone needs to cool down"
        @unknown default: label = "Unknown"; note = nil
        }
        output?(.thermalState, SensorSample(
            values: [Double(state.rawValue)],
            state: label,
            note: note
        ))
    }
}
