import AVFoundation
import CoreLocation
import CoreMotion
import UIKit

enum PermissionStatus: Sendable, Equatable {
    case notDetermined
    case granted
    case denied

    var isGranted: Bool { self == .granted }
}

/// Reads and requests the four permissions Readout can need, and nothing else (SPEC §10).
///
/// Location is handled by `LocationProvider`, because the app keeps a single
/// `CLLocationManager` (R-63); this type asks that provider rather than making its own.
@MainActor
@Observable
final class PermissionCoordinator {
    private(set) var statuses: [SensorPermission: PermissionStatus] = [:]

    /// Set by `SensorHub` once the providers exist.
    weak var locationProvider: LocationProvider?

    private let pedometer = CMPedometer()

    init() {
        refresh()
    }

    func status(of permission: SensorPermission) -> PermissionStatus {
        statuses[permission] ?? .notDetermined
    }

    func refresh() {
        statuses[.motionFitness] = Self.motionStatus()
        statuses[.microphone] = Self.microphoneStatus()
        statuses[.camera] = Self.cameraStatus()
        statuses[.locationWhenInUse] = locationProvider?.permissionStatus ?? Self.locationStatus()
    }

    /// Asks for a permission, having already shown the explanation card (R-54).
    func request(_ permission: SensorPermission) async {
        switch permission {
        case .motionFitness:
            await requestMotionFitness()
        case .locationWhenInUse:
            locationProvider?.requestAuthorization()
        case .microphone:
            _ = await AVAudioApplication.requestRecordPermission()
        case .camera:
            _ = await AVCaptureDevice.requestAccess(for: .video)
        }
        refresh()
    }

    /// Opens the app's own page in Settings, for a permission already refused (R-55).
    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: - Status reading

    private static func motionStatus() -> PermissionStatus {
        switch CMPedometer.authorizationStatus() {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func microphoneStatus() -> PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        case .undetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func cameraStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    private static func locationStatus() -> PermissionStatus {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }

    /// There is no explicit request API for Motion & Fitness: asking the pedometer for data
    /// is what triggers the system prompt.
    private func requestMotionFitness() async {
        guard CMPedometer.isStepCountingAvailable() else { return }
        let end = Date.now
        let start = end.addingTimeInterval(-60)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pedometer.queryPedometerData(from: start, to: end) { _, _ in
                continuation.resume()
            }
        }
    }
}
