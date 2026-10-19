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
    /// The latest value per reading, at provider rate.
    private(set) var samples: [ReadingID: SensorSample] = [:]

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

    private var buffers: [ReadingID: SampleBuffer] = [:]
    /// A short trail of the tile's single value, kept separately so drawing 19 sparklines
    /// never walks the full history ring.
    private var trails: [ReadingID: [Double]] = [:]
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
        for reading in ReadingID.allCases {
            if let provider = providersByReading[reading], provider.isSupported(reading) {
                providersBySupportedReading[reading] = provider
            } else {
                #if targetEnvironment(simulator)
                // The Simulator has almost no sensors, so synthetic data stands in (R-71).
                providersBySupportedReading[reading] = mock
                #endif
            }
        }
        apply(settings)
    }

    // MARK: - Settings

    /// Pushes the user's preferences into the providers that need them.
    func apply(_ settings: AppSettings) {
        motion.includesGravity = settings.accelerationIncludesGravity
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

    /// Stops every sensor without forgetting who asked for it, so the foreground can resume
    /// exactly what was running (R-64).
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        for (reading, provider) in running {
            provider.stop(reading)
        }
        running.removeAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        permissions.refresh()
        for reading in leases.keys {
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
        samples[reading]
    }

    /// The gravity vector the spirit level works from (R-32). On an iPhone this is Core
    /// Motion's own vector; where only an attitude exists — the Simulator's synthetic
    /// orientation — it is rebuilt from pitch and roll so the tool stays demoable (R-71).
    var gravity: Vector3? {
        if let gravity = motion.gravity { return gravity }
        guard let sample = samples[.orientation], sample.values.count >= 2 else { return nil }
        return LevelMaths.gravity(pitchDegrees: sample.values[0], rollDegrees: sample.values[1])
    }

    func buffer(_ reading: ReadingID) -> SampleBuffer {
        buffers[reading] ?? SampleBuffer()
    }

    func resetStats(_ reading: ReadingID) {
        buffers[reading]?.resetStats()
        if reading == .soundLevel { audio.resetPeak() }
    }

    func clearHistory(_ reading: ReadingID) {
        buffers[reading]?.removeAll()
        trails[reading] = nil
    }

    /// The last few seconds of a tile's single value, for its sparkline (R-16).
    func trail(_ reading: ReadingID) -> [Double] {
        trails[reading] ?? []
    }

    private func receive(_ reading: ReadingID, _ sample: SensorSample) {
        samples[reading] = sample
        sampleObserver?(reading, sample)
        let appended = buffers[reading, default: SampleBuffer()].append(sample)
        // A non-finite value would put a NaN into the sparkline's path, which CoreGraphics
        // rejects and draws as a break in the line.
        guard appended,
              let value = ReadingCatalog.descriptor(reading).summaryValue(sample),
              value.isFinite
        else { return }
        var trail = trails[reading] ?? []
        trail.append(value)
        if trail.count > Self.trailLength {
            trail.removeFirst(trail.count - Self.trailLength)
        }
        trails[reading] = trail
    }

    /// About six seconds at the 10 Hz the history buffer decimates to.
    private static let trailLength = 60
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
