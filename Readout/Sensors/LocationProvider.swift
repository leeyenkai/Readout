import CoreLocation
import Foundation

/// The location group and heading, from the app's single `CLLocationManager` (R-63).
@MainActor
@Observable
final class LocationProvider: NSObject, SensorProvider {
    let readings: Set<ReadingID> = [.coordinates, .gpsAltitude, .speed, .course, .locationAccuracy, .heading]
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Set from Settings; magnetic north needs no location permission (SPEC §3, reading 5).
    var usesTrueNorth = true

    private(set) var permissionStatus: PermissionStatus = .notDetermined
    /// iOS asks the user to wave the phone when this is poor (R-69).
    private(set) var headingAccuracy: Double = -1
    private(set) var lastLocation: CLLocation?
    private(set) var lastHeading: CLHeading?

    private let manager = CLLocationManager()
    private var active: Set<ReadingID> = []

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        permissionStatus = Self.status(from: manager.authorizationStatus)
    }

    func isSupported(_ reading: ReadingID) -> Bool {
        switch reading {
        case .heading: CLLocationManager.headingAvailable()
        default: CLLocationManager.locationServicesEnabled()
        }
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard isSupported(reading) else { return }
        active.insert(reading)
        if reading == .heading {
            manager.startUpdatingHeading()
        }
        if reading != .heading || usesTrueNorth {
            manager.startUpdatingLocation()
        }
        // Replay the last fix so a freshly opened view is not blank.
        if let lastLocation { publish(lastLocation) }
        if let lastHeading { publish(lastHeading) }
    }

    func stop(_ reading: ReadingID) {
        active.remove(reading)
        if reading == .heading {
            manager.stopUpdatingHeading()
        }
        if active.isEmpty {
            manager.stopUpdatingLocation()
        }
    }

    func requestAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    // MARK: - Publishing

    private func publish(_ location: CLLocation) {
        lastLocation = location
        let time = location.timestamp
        if active.contains(.coordinates) {
            output?(.coordinates, SensorSample(
                time: time,
                values: [location.coordinate.latitude, location.coordinate.longitude]
            ))
        }
        if active.contains(.gpsAltitude) {
            output?(.gpsAltitude, SensorSample(time: time, values: [location.altitude]))
        }
        if active.contains(.speed) {
            let speed = max(location.speed, 0)
            output?(.speed, SensorSample(
                time: time,
                values: [speed],
                note: location.speed < 0 ? "No fix" : nil
            ))
        }
        if active.contains(.course) {
            let course = location.course
            output?(.course, SensorSample(
                time: time,
                values: [max(course, 0)],
                note: course < 0 ? "Stand still and no course is reported" : nil
            ))
        }
        if active.contains(.locationAccuracy) {
            output?(.locationAccuracy, SensorSample(
                time: time,
                values: [location.horizontalAccuracy, location.verticalAccuracy]
            ))
        }
    }

    private func publish(_ heading: CLHeading) {
        lastHeading = heading
        headingAccuracy = heading.headingAccuracy
        let degrees = usesTrueNorth && heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading
        guard active.contains(.heading) else { return }
        output?(.heading, SensorSample(
            time: heading.timestamp,
            values: [degrees],
            note: usesTrueNorth && heading.trueHeading >= 0 ? "True north" : "Magnetic north"
        ))
    }

    private static func status(from authorization: CLAuthorizationStatus) -> PermissionStatus {
        switch authorization {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

// Core Location delivers these on the queue the manager was created on — the main queue here.
// The protocol predates Swift concurrency and carries no actor annotation, so the conformance
// is marked `@preconcurrency` and the methods stay on the main actor with the rest of the class.
extension LocationProvider: @preconcurrency CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        publish(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        publish(newHeading)
    }

    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool {
        // Lets iOS put up its own figure-of-eight prompt when heading accuracy is poor (R-69).
        true
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        permissionStatus = Self.status(from: manager.authorizationStatus)
        guard permissionStatus.isGranted, !active.isEmpty else { return }
        manager.startUpdatingLocation()
        if active.contains(.heading) { manager.startUpdatingHeading() }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure is normal indoors; the accuracy reading already tells the story.
    }
}
