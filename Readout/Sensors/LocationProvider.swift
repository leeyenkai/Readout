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

    /// Called when iOS reports a new authorisation state. Set by `SensorHub`, which uses it
    /// to start the readings that were already leased but waiting on the answer (R-54).
    ///
    /// Core Location is the one permission whose request cannot be awaited:
    /// `requestWhenInUseAuthorization()` returns long before the prompt is dismissed, so the
    /// caller has nothing to wait for and must be told afterwards instead.
    var onAuthorizationChange: (() -> Void)?

    private(set) var permissionStatus: PermissionStatus = .notDetermined
    /// iOS asks the user to wave the phone when this is poor (R-69).
    private(set) var headingAccuracy: Double = -1
    private(set) var lastLocation: CLLocation?
    private(set) var lastHeading: CLHeading?

    private let manager = CLLocationManager()
    private var active: Set<ReadingID> = []

    /// Whether this build may keep running in the background on Core Location's account.
    ///
    /// `allowsBackgroundLocationUpdates` raises if the `location` background mode is not
    /// declared, so the bundle is asked rather than assumed: a build that drops the mode
    /// should lose the feature, not crash on the first long recording (R-82).
    static let hasLocationBackgroundMode: Bool = {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("location") ?? false
    }()

    /// Set only while a recording that may continue in the background is running (R-82).
    ///
    /// It is cleared the moment that recording stops. Leaving it on would let Readout hold
    /// the app alive with nothing to show for it, and would keep the blue indicator lit for a
    /// user who is no longer recording anything.
    var allowsBackgroundUpdates = false {
        didSet {
            guard allowsBackgroundUpdates != oldValue, Self.hasLocationBackgroundMode else { return }
            manager.allowsBackgroundLocationUpdates = allowsBackgroundUpdates
            // iOS pauses location updates when it decides the device has stopped moving,
            // which on a train means a log that quietly stops at the first long platform.
            manager.pausesLocationUpdatesAutomatically = !allowsBackgroundUpdates
        }
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.headingFilter = 1
        permissionStatus = Self.status(from: manager.authorizationStatus)
    }

    /// Every iPhone can locate itself, so the location group is always offered and the
    /// permission state decides what the tile shows. `locationServicesEnabled()` is not
    /// asked: Apple documents it as blocking, and the hub resolves support for all 19
    /// readings during launch (R-7). Services switched off device-wide reads as a refused
    /// permission, which is what it amounts to, rather than as missing hardware.
    func isSupported(_ reading: ReadingID) -> Bool {
        switch reading {
        case .heading: CLLocationManager.headingAvailable()
        default: true
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
        let previous = permissionStatus
        permissionStatus = Self.status(from: manager.authorizationStatus)
        guard permissionStatus != previous else { return }
        // The hub decides what to start: a reading leased while the prompt was still up has
        // no entry in `active`, so starting the manager here would leave the updates arriving
        // with nothing to publish them to. Core Location also calls this once as the delegate
        // is set, which is why an unchanged state is ignored.
        onAuthorizationChange?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // A transient failure is normal indoors; the accuracy reading already tells the story.
    }
}
