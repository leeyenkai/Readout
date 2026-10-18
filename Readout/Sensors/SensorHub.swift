import Foundation
import SwiftUI

/// The single owner of every sensor in the app (R-63).
///
/// Views never touch Core Motion, Core Location or AVFoundation. They call `activate(_:)` when
/// they appear and `deactivate(_:)` when they disappear; a provider starts on the first
/// activation and stops on the last one, or when the app leaves the foreground (R-64).
@MainActor
@Observable
final class SensorHub {
    /// The latest value per reading, at provider rate.
    private(set) var samples: [ReadingID: SensorSample] = [:]

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
    /// Activation counts per requested rate, so one view wanting display rate does not get
    /// downgraded when another view wanting 10 Hz goes away.
    private var counts: [ReadingID: [ActivationRate: Int]] = [:]
    private var running: [ReadingID: any SensorProvider] = [:]
    private var providersByReading: [ReadingID: any SensorProvider] = [:]
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
        apply(settings)
    }

    // MARK: - Settings

    /// Pushes the user's preferences into the providers that need them.
    func apply(_ settings: AppSettings) {
        motion.includesGravity = settings.accelerationIncludesGravity
        location.usesTrueNorth = settings.usesTrueNorth
        audio.calibrationOffset = settings.soundCalibrationOffset
        audio.respondsFast = settings.soundRespondsFast
        light.calibration = settings.lightCalibration
    }

    // MARK: - Activation

    func activate(_ reading: ReadingID, rate: ActivationRate = .standard) {
        counts[reading, default: [:]][rate, default: 0] += 1
        startIfNeeded(reading)
    }

    func deactivate(_ reading: ReadingID, rate: ActivationRate = .standard) {
        guard var rates = counts[reading], let count = rates[rate] else { return }
        if count <= 1 {
            rates[rate] = nil
        } else {
            rates[rate] = count - 1
        }
        counts[reading] = rates.isEmpty ? nil : rates
        if counts[reading] == nil {
            running[reading]?.stop(reading)
            running[reading] = nil
        } else {
            startIfNeeded(reading)
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
        for reading in counts.keys {
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
        counts[reading]?.filter { $0.value > 0 }.keys.max()
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
        if let provider = providersByReading[reading], provider.isSupported(reading) {
            return provider
        }
        #if targetEnvironment(simulator)
        // The Simulator has almost no sensors, so synthetic data stands in (R-71).
        return mock
        #else
        return nil
        #endif
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
        let appended = buffers[reading, default: SampleBuffer()].append(sample)
        guard appended, let value = ReadingCatalog.descriptor(reading).summaryValue(sample) else { return }
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
