import CoreLocation
import Foundation
import UIKit

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
    var onAuthorizationChange: (() -> Void)?

    /// Callers waiting in `requestAuthorization()` for the user to answer the prompt.
    private var authorizationWaiters: [CheckedContinuation<Void, Never>] = []
    private var authorizationWatchdog: Task<Void, Never>?

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

    /// Asks for When In Use and returns once the user has answered.
    ///
    /// `requestWhenInUseAuthorization()` itself returns long before the prompt is dismissed.
    /// Treating it as the answer is what made a first journey recording quietly start without
    /// its location readings: they were still "not determined" on the next line, so they were
    /// left out, the session was judged foreground-only, and locking the phone ended it.
    ///
    /// The answer arrives through `locationManagerDidChangeAuthorization`. A watchdog covers
    /// the case where no prompt ever appears — Location Services switched off for the whole
    /// phone puts up a different alert and never reports back — by giving up once the app has
    /// been back in front for a moment, so the caller is never left waiting for ever.
    func requestAuthorization() async {
        guard permissionStatus == .notDetermined else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            authorizationWaiters.append(continuation)
            guard authorizationWaiters.count == 1 else { return }
            manager.requestWhenInUseAuthorization()
            startAuthorizationWatchdog()
        }
    }

    private func startAuthorizationWatchdog() {
        authorizationWatchdog?.cancel()
        authorizationWatchdog = Task { [weak self] in
            var activeFor: TimeInterval = 0
            var sawPrompt = false
            let step: TimeInterval = 0.25
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(step))
                guard let self, !self.authorizationWaiters.isEmpty else { return }
                // While the prompt is up the app is inactive; only time spent back in front
                // with no answer counts towards giving up. Until a prompt has been seen at
                // all the wait is longer, so one slow to appear is not taken for no answer.
                if UIApplication.shared.applicationState == .active {
                    activeFor += step
                } else {
                    sawPrompt = true
                    activeFor = 0
                }
                if activeFor >= (sawPrompt ? 1.5 : 6) {
                    self.resumeAuthorizationWaiters()
                    return
                }
            }
        }
    }

    private func resumeAuthorizationWaiters() {
        authorizationWatchdog?.cancel()
        authorizationWatchdog = nil
        let waiters = authorizationWaiters
        authorizationWaiters = []
        waiters.forEach { $0.resume() }
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
        // Core Location marks a figure it cannot give with a negative accuracy or value. Those
        // are published as "no value" rather than clamped to zero: a course of 0 is due north,
        // and a speed of 0 drags every average towards standing still. A missing value leaves
        // an empty cell in the CSV and is skipped by the statistics (R-45, P-2).
        if active.contains(.gpsAltitude) {
            let isValid = location.verticalAccuracy >= 0
            output?(.gpsAltitude, SensorSample(
                time: time,
                values: [isValid ? location.altitude : .nan],
                note: isValid ? nil : "No vertical fix yet"
            ))
        }
        if active.contains(.speed) {
            let isValid = location.speed >= 0
            output?(.speed, SensorSample(
                time: time,
                values: [isValid ? location.speed : .nan],
                note: isValid ? nil : "No speed reported yet"
            ))
        }
        if active.contains(.course) {
            let isValid = location.course >= 0
            output?(.course, SensorSample(
                time: time,
                values: [isValid ? location.course : .nan],
                note: isValid ? nil : "No course while standing still"
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
        // Every fix, oldest first. Core Location batches them when delivery is delayed — which
        // is routine in the background — and publishing only the last one left gaps in a
        // journey's CSV and its route.
        for location in locations {
            publish(location)
        }
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
        if permissionStatus != .notDetermined {
            resumeAuthorizationWaiters()
        }
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
