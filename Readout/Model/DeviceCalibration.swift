import Foundation

/// Per-model corrections for the two readings that are estimates rather than measurements:
/// sound, from microphone level metering, and light, from camera exposure (R-10, R-66).
///
/// Both depend on hardware that differs between iPhone models — microphone sensitivity and
/// placement, lens aperture and sensor response — so a single conversion cannot be right for
/// every phone. The user's own offset in Settings sits on top of whatever is found here.
///
/// **The tables below are deliberately empty.** Filling one in needs the model in hand and a
/// calibrated reference meter to compare against; a plausible-looking number put here without
/// that measurement would make the reading look more trustworthy than it is, which is exactly
/// what SPEC P-2 rules out. Until a model is measured it gets the neutral value, and the
/// reading keeps its "≈" and its estimate note (R-72).
enum DeviceCalibration {
    /// The hardware identifier, for example `iPhone17,1`. Not the marketing name: Apple does
    /// not expose that, and the identifier is what a calibration measurement is filed under.
    static let modelIdentifier: String = {
        #if targetEnvironment(simulator)
        // `uname` reports the Mac's own architecture in the Simulator, which is no use as a
        // calibration key and reads as nonsense in Settings. The device being simulated is
        // in the environment instead.
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"],
           !simulated.isEmpty {
            return simulated
        }
        #endif
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
    }()

    /// Added to the dB figure before the user's own offset, in decibels.
    ///
    /// To add a model: measure a steady tone with a calibrated meter, read Readout's figure
    /// with the user offset at zero, and record the difference.
    ///
    ///     "iPhone17,1": -3.5,   // measured against a Class 2 meter at 1 kHz
    ///
    static let soundOffsets: [String: Double] = [:]

    /// Multiplies the lux estimate before the user's own multiplier.
    ///
    ///     "iPhone17,1": 1.15,   // rear camera, against a reference lux meter at 500 lux
    ///
    static let lightMultipliers: [String: Double] = [:]

    static func soundOffset(for model: String = modelIdentifier) -> Double {
        soundOffsets[model] ?? 0
    }

    static func lightMultiplier(for model: String = modelIdentifier) -> Double {
        lightMultipliers[model] ?? 1
    }

    /// Whether this iPhone has been measured. Settings says so plainly, so nobody assumes a
    /// calibration that does not exist.
    static var hasEntryForThisDevice: Bool {
        soundOffsets[modelIdentifier] != nil || lightMultipliers[modelIdentifier] != nil
    }
}
