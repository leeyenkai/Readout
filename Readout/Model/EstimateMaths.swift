import Foundation

/// Turning a microphone's signal level into an estimated sound pressure level.
///
/// This is an estimate and nothing more: a real sound level meter is calibrated against a
/// reference tone, and iOS gives no absolute figure. Kept here as pure functions so the
/// conversion is covered by tests (R-66, R-72).
enum SoundLevelMaths {
    /// Assumed sound pressure level at digital full scale, in dB. A working guess for iPhone
    /// microphones until per-model calibration exists (SPEC §13 Q-5).
    static let fullScaleReference: Double = 96

    /// The quietest level worth showing; below this the microphone is reporting its own noise.
    static let floor: Double = 0
    static let ceiling: Double = 140

    /// Converts a linear RMS amplitude (0...1) into an estimated dB SPL.
    static func decibels(rms: Double, calibrationOffset: Double = 0) -> Double {
        guard rms > 0 else { return floor }
        let dBFS = 20 * log10(min(rms, 1))
        return min(max(dBFS + fullScaleReference + calibrationOffset, floor), ceiling)
    }

    /// Exponential smoothing factor for a time constant, used for fast and slow response (R-34).
    static func smoothing(timeConstant: TimeInterval, interval: TimeInterval) -> Double {
        guard timeConstant > 0 else { return 1 }
        return 1 - exp(-interval / timeConstant)
    }
}

/// Turning camera exposure settings into an estimated illuminance.
///
/// iOS exposes no ambient light sensor, so brightness is inferred from how the camera chose to
/// expose the scene. Pure functions, so the maths is testable without a camera (R-9, R-67).
enum LightMaths {
    /// Incident-light calibration constant. 2.5 is the conventional value for converting an
    /// ISO 100 exposure value to lux.
    static let calibrationConstant: Double = 2.5

    /// Exposure value normalised to ISO 100.
    ///
    /// - Parameters:
    ///   - aperture: f-number, for example 1.78.
    ///   - exposureDuration: shutter time in seconds.
    ///   - iso: film-speed equivalent the camera chose.
    static func exposureValue(aperture: Double, exposureDuration: TimeInterval, iso: Double) -> Double? {
        guard aperture > 0, exposureDuration > 0, iso > 0 else { return nil }
        return log2((aperture * aperture) / exposureDuration) + log2(100 / iso)
    }

    /// Approximate illuminance in lux for an ISO 100 exposure value.
    static func lux(exposureValue: Double, calibration: Double = 1) -> Double {
        max(calibrationConstant * pow(2, exposureValue) * calibration, 0)
    }

    /// Convenience: straight from the camera's three numbers to lux.
    static func lux(
        aperture: Double,
        exposureDuration: TimeInterval,
        iso: Double,
        calibration: Double = 1
    ) -> Double? {
        guard let ev = exposureValue(aperture: aperture, exposureDuration: exposureDuration, iso: iso) else {
            return nil
        }
        return lux(exposureValue: ev, calibration: calibration)
    }
}
