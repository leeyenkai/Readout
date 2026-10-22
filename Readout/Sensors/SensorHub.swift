import Foundation
import SwiftUI

/// The single owner of every sensor in the app (R-63).
///
/// Views never touch Core Motion, Core Location or AVFoundation. They take a lease on a
/// reading when they appear and hand it back when they disappear; a provider starts on the
/// first lease and stops when the last one goes, or when the app leaves the foreground (R-64).
@MainActor
@Observable
final class SensorHub {
    /// The latest value, history and sparkline trail of each reading, one observable cell
    /// apiece and all made up front.
    ///
    /// These used to be three dictionaries on the hub itself, so a view that read one reading
    /// was invalidated by every other reading's samples as well — the detail view of the
    /// barometer redrew at the accelerometer's 60 Hz. The dictionary is fixed after `init` and
    /// not itself observed; each cell is, so a view now follows only what it reads.
    @ObservationIgnored private let cells: [ReadingID: ReadingCell]

    /// Called with every sample a provider delivers, before the history buffer decimates it
    /// to 10 Hz. Set by `RecordingService`, which needs the full rate to record at 50 Hz
    /// (R-39, R-65).
    var sampleObserver: ((ReadingID, SensorSample) -> Void)?

    let permissions = PermissionCoordinator()
    let motion = MotionProvider()
    let location = LocationProvider()
    let audio = AudioLevelProvider()
    let light = LightProvider()

    private let altimeter = AltimeterProvider()
    private let pedometer = PedometerProvider()
    private let device = DeviceProvider()
    private let mock = MockSensorSource()

    /// The outstanding leases per reading and the rate each one asked for, so a view wanting
    /// display rate is not downgraded when another view wanting 10 Hz goes away.
    private var leases: [ReadingID: [UUID: ActivationRate]] = [:]
    private var running: [ReadingID: any SensorProvider] = [:]
    private var providersByReading: [ReadingID: any SensorProvider] = [:]
    /// Resolved once at init. Hardware support does not change while the app runs, and
    /// probing for it is expensive enough to matter: `DeviceProvider` switches proximity
    /// monitoring on and off to test for it, and Core Location's check can block (R-7).
    private var providersBySupportedReading: [ReadingID: any SensorProvider] = [:]
    private var isSuspended = false
    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        cells = Dictionary(uniqueKeysWithValues: ReadingID.allCases.map { reading in
            (reading, ReadingCell(wraps: ReadingCatalog.descriptor(reading).channelWraps))
        })
        let providers: [any SensorProvider] = [motion, altimeter, pedometer, location, audio, light, device]
        for provider in providers {
            for reading in provider.readings {
                providersByReading[reading] = provider
            }
        }
        for provider in providers {
            provider.output = { [weak self] reading, sample in
                self?.receive(reading, sample)
            }
        }
        mock.output = { [weak self] reading, sample in
            self?.receive(reading, sample)
        }
        permissions.locationProvider = location
        // Location's answer arrives after the request returns, so the provider reports it
        // back and whatever was leased in the meantime starts then (R-54).
        location.onAuthorizationChange = { [weak self] in
            guard let self else { return }
            permissions.refresh()
            motion.isLocationAuthorized = location.permissionStatus.isGranted
            restartLeases()
        }
        for reading in ReadingID.allCases {
            #if targetEnvironment(simulator)
            // The Simulator has none of these sensors, so every reading comes from the
            // synthetic source and the whole interface stays demoable (R-71).
            //
            // All of them, not only the ones the frameworks admit to lacking: Core Location
            // reports itself as available there and then never produces a fix, which left
            // the location group — and the compass's position panel — waiting for ever.
            providersBySupportedReading[reading] = mock
            #else
            if let provider = providersByReading[reading], provider.isSupported(reading) {
                providersBySupportedReading[reading] = provider
            }
            #endif
        }
        apply(settings)
    }

    // MARK: - Settings

    /// Pushes the user's preferences into the providers that need them.
    func apply(_ settings: AppSettings) {
        motion.includesGravity = settings.accelerationIncludesGravity
        mock.includesGravity = settings.accelerationIncludesGravity
        motion.isLocationAuthorized = location.permissionStatus.isGranted
        location.usesTrueNorth = settings.usesTrueNorth
        // The per-model correction first, then the user's own on top of it (R-10, R-66).
        audio.calibrationOffset = DeviceCalibration.soundOffset() + settings.soundCalibrationOffset
        audio.respondsFast = settings.soundRespondsFast
        light.calibration = DeviceCalibration.lightMultiplier() * settings.lightCalibration
    }

    // MARK: - Activation

    /// Claims a reading for as long as the caller holds the returned lease.
    @discardableResult
    func activate(_ reading: ReadingID, rate: ActivationRate = .standard) -> SensorLease {
        let lease = SensorLease(reading: reading)
        leases[reading, default: [:]][lease.id] = rate
        startIfNeeded(reading)
        return lease
    }

    /// Hands a lease back. Releasing one twice, or releasing nothing, does nothing — which is
    /// what makes it safe to call from `onDisappear` without tracking whether the matching
    /// `activate` ever happened.
    func release(_ lease: SensorLease?) {
        guard let lease, var held = leases[lease.reading] else { return }
        guard held.removeValue(forKey: lease.id) != nil else { return }
        leases[lease.reading] = held.isEmpty ? nil : held
        if held.isEmpty {
            running[lease.reading]?.stop(lease.reading)
            running[lease.reading] = nil
        } else {
            startIfNeeded(lease.reading)
        }
    }

    func isActive(_ reading: ReadingID) -> Bool {
        running[reading] != nil
    }

    /// Whether this build can keep a recording running in the background at all (R-82).
    var canRecordInBackground: Bool { LocationProvider.hasLocationBackgroundMode }

    /// Lets Core Location hold the app alive for a running recording, and takes it away again
    /// when that recording stops (R-82). Only `RecordingService` calls this.
    func setBackgroundLocationUpdates(_ enabled: Bool) {
        location.allowsBackgroundUpdates = enabled
    }

    /// Stops every sensor without forgetting who asked for it, so the foreground can resume
    /// exactly what was running (R-64).
    ///
    /// `kept` is what a recording that carries on in the background is logging (R-82). Only
    /// those keep running. Leaving the hub alone altogether, as it used to for such a
    /// recording, also kept every reading the screen behind it had leased — an open Sound
    /// meter kept the microphone live with Readout in the background, which R-83 rules out.
    func suspend(keeping kept: Set<ReadingID> = []) {
        guard !isSuspended else { return }
        isSuspended = true
        for (reading, provider) in running where !kept.contains(reading) {
            provider.stop(reading)
            running[reading] = nil
        }
    }

    /// Stops what a background recording kept running, once that recording has ended. Its
    /// own leases are gone by then, but a screen behind it may lease the same reading — the
    /// compass holding Coordinates — and that lease alone kept location running with Readout
    /// in the background. It all comes back on resume. Does nothing in the foreground.
    func stopKeptReadings() {
        guard isSuspended else { return }
        for (reading, provider) in running {
            provider.stop(reading)
            running[reading] = nil
        }
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        permissions.refresh()
        restartLeases()
    }

    /// Asks for a permission and then starts whatever was already waiting on it (R-54).
    ///
    /// A view takes its lease the moment it appears, before the user has answered the prompt,
    /// so the lease is outstanding but the provider is not running. Without this second step
    /// the reading stays blank until the view is left and opened again — which is what the
    /// compass did after location had just been allowed.
    func requestPermission(_ permission: SensorPermission) async {
        await permissions.request(permission)
        restartLeases()
    }

    /// Starts every leased reading that is allowed to run and is not running yet.
    private func restartLeases() {
        for reading in leases.keys where !isActive(reading) {
            startIfNeeded(reading)
        }
    }

    private func startIfNeeded(_ reading: ReadingID) {
        guard !isSuspended, let rate = requestedRate(reading) else { return }
        guard availability(reading).isUsable else { return }
        guard let provider = provider(for: reading) else { return }
        provider.start(reading, rate: rate)
        running[reading] = provider
    }

    private func requestedRate(_ reading: ReadingID) -> ActivationRate? {
        leases[reading]?.values.max()
    }

    // MARK: - Availability

    func availability(_ reading: ReadingID) -> ReadingAvailability {
        guard provider(for: reading) != nil else { return .unavailable }
        if let permission = ReadingCatalog.descriptor(reading).permission,
           !isPermissionBypassed {
            switch permissions.status(of: permission) {
            case .notDetermined: return .needsPermission(permission)
            case .denied: return .denied(permission)
            case .granted: break
            }
        }
        return isActive(reading) ? .live : .ready
    }

    /// Readings this device can show at all, in catalog order (R-7, R-21).
    func availableReadings(in group: ReadingGroup) -> [ReadingDescriptor] {
        ReadingCatalog.readings(in: group).filter { availability($0.id) != .unavailable }
    }

    private func provider(for reading: ReadingID) -> (any SensorProvider)? {
        providersBySupportedReading[reading]
    }

    /// In the Simulator there is no real sensor to protect, and no way to answer a
    /// Motion & Fitness prompt, so the permission gate is skipped to keep the UI usable.
    private var isPermissionBypassed: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    // MARK: - Values and history

    func sample(_ reading: ReadingID) -> SensorSample? {
        cells[reading]?.sample
    }

    /// The gravity vector the spirit level works from (R-32). On an iPhone this is Core
    /// Motion's own vector; where only an attitude exists — the Simulator's synthetic
    /// orientation — it is rebuilt from that, so the tool stays demoable (R-71).
    var gravity: Vector3? {
        if let gravity = motion.gravity { return gravity }
        return syntheticAttitude.map(AttitudeMaths.gravity)
    }

    /// The phone's attitude, for the 3D view (R-86). Core Motion's quaternion on an iPhone;
    /// rebuilt from the synthetic pitch, roll and yaw in the Simulator.
    var attitude: Attitude? {
        motion.attitude ?? syntheticAttitude
    }

    /// The push the user is giving the phone, in g, with gravity taken out whatever the
    /// Include gravity setting says (R-86).
    var userAcceleration: Vector3? {
        if let user = motion.userAcceleration { return user }
        #if targetEnvironment(simulator)
        guard let sample = cells[.acceleration]?.sample, sample.values.count >= 3 else { return nil }
        var user = Vector3(x: sample.values[0], y: sample.values[1], z: sample.values[2])
        if settings.accelerationIncludesGravity, let gravity {
            user = Vector3(x: user.x - gravity.x, y: user.y - gravity.y, z: user.z - gravity.z)
        }
        return user
        #else
        return nil
        #endif
    }

    /// The Simulator's stand-in for Core Motion's attitude. Never used on an iPhone: there
    /// the readings' last samples outlive a stop, and a level or 3D view rebuilt from them
    /// would show the old tilt — or the last push — as if it were live (P-2).
    private var syntheticAttitude: Attitude? {
        #if targetEnvironment(simulator)
        guard let sample = cells[.orientation]?.sample, sample.values.count >= 3 else { return nil }
        return AttitudeMaths.attitude(
            pitchDegrees: sample.values[0],
            rollDegrees: sample.values[1],
            yawDegrees: sample.values[2]
        )
        #else
        nil
        #endif
    }

    /// Why a reading a view is holding has stopped arriving, when iOS says so. Shown in
    /// place of the value: a number that has stopped being true is worse than none (P-2).
    ///
    /// iOS reports it for the microphone — a call, Siri or another app takes it — and for the
    /// camera, which another app or the phone's own heat can take away. Both come back by
    /// themselves when they are handed back (R-34, R-35, R-66).
    func stalledReason(_ reading: ReadingID) -> String? {
        guard isActive(reading) else { return nil }
        switch reading {
        case .soundLevel where audio.status == .interrupted:
            return "Paused — something else is using the microphone"
        case .light where light.isInterrupted:
            return "Paused — the camera is not available right now"
        default:
            return nil
        }
    }

    func buffer(_ reading: ReadingID) -> SampleBuffer {
        cells[reading]?.buffer ?? SampleBuffer()
    }

    /// Starts the statistics again. A view whose stats read "since you opened this" calls
    /// it as it opens; the history is kept, so the chart does not empty (R-26).
    func resetStats(_ reading: ReadingID) {
        cells[reading]?.buffer.resetStats()
    }

    func clearHistory(_ reading: ReadingID) {
        guard let cell = cells[reading] else { return }
        cell.buffer.removeAll()
        cell.trail = []
    }

    /// The last few seconds of a tile's single value, for its sparkline (R-16).
    func trail(_ reading: ReadingID) -> [Double] {
        cells[reading]?.trail ?? []
    }

    private func receive(_ reading: ReadingID, _ sample: SensorSample) {
        guard let cell = cells[reading] else { return }
        cell.sample = sample
        sampleObserver?(reading, sample)
        // Asked first, so a sample the buffer would drop is not a change to it: anything
        // observing the history redraws at the history's 10 Hz, not at the provider's rate.
        guard cell.buffer.accepts(sample) else { return }
        cell.buffer.append(sample)
        // A non-finite value would put a NaN into the sparkline's path, which CoreGraphics
        // rejects and draws as a break in the line.
        guard let value = ReadingCatalog.descriptor(reading).summaryValue(sample), value.isFinite else {
            return
        }
        var trail = cell.trail
        trail.append(value)
        if trail.count > Self.trailLength {
            trail.removeFirst(trail.count - Self.trailLength)
        }
        cell.trail = trail
    }

    /// About six seconds at the 10 Hz the history buffer decimates to.
    private static let trailLength = 60
}

/// One reading's live state: its latest sample, the decimated history behind its chart and
/// statistics, and the trail behind its sparkline. Observed on its own, so a view follows only
/// the readings it shows.
@MainActor
@Observable
final class ReadingCell {
    var sample: SensorSample?
    var buffer: SampleBuffer
    var trail: [Double] = []

    init(wraps: [AngleWrap?]) {
        buffer = SampleBuffer(wraps: wraps)
    }
}

/// One view's claim on one reading, handed out by `SensorHub.activate(_:rate:)`.
///
/// A lease rather than a matching `deactivate(_:rate:)` call because the pairing used to be
/// maintained by hand across six views: a view that activated twice, or gave back a rate it
/// had not asked for, left the provider running for the rest of the app's life — with the
/// microphone or camera indicator still lit (R-64).
struct SensorLease: Hashable, Identifiable {
    let id = UUID()
    let reading: ReadingID
}
