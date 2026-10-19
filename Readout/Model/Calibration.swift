import Foundation

/// Working out the user's own correction for the two readings that are estimates rather than
/// measurements, from a figure read off a reference meter (R-10, R-66, Q-5).
///
/// Readout cannot calibrate itself. iOS gives no absolute figure for either sound pressure or
/// illuminance, so the only route to a trustworthy number is to compare against an instrument
/// that has one. This is the arithmetic behind that comparison, kept pure so the tests cover
/// it without hardware, and deliberately narrow: a correction larger than the estimate's own
/// spread is refused rather than applied, because it nearly always means the two meters were
/// not measuring the same thing.
enum Calibration {
    /// How far the user's own sound correction may go, in dB. Beyond this the estimate is not
    /// being corrected, it is being overruled.
    static let soundOffsetRange: ClosedRange<Double> = -20...20
    /// How far the user's own light correction may go, as a multiplier.
    static let lightMultiplierRange: ClosedRange<Double> = 0.25...4

    /// Why a figure could not be turned into a correction.
    enum Failure: Error, Equatable {
        /// Not a number, or a figure the reading cannot take — a lux or dB value of zero.
        case notAReading
        /// The correction needed is further than Readout is willing to call a calibration.
        case tooFarApart
    }

    /// The sound offset that would make Readout agree with a reference meter.
    ///
    /// `measured` is what Readout shows now, which already carries `currentOffset`, so the
    /// correction in force is kept rather than measured a second time.
    static func soundOffset(
        measured: Double,
        reference: Double,
        currentOffset: Double
    ) -> Result<Double, Failure> {
        guard measured.isFinite, reference.isFinite, reference > 0, currentOffset.isFinite else {
            return .failure(.notAReading)
        }
        // Half a decibel: finer than the estimate itself can honestly claim.
        let wanted = ((currentOffset + reference - measured) * 2).rounded() / 2
        guard soundOffsetRange.contains(wanted) else { return .failure(.tooFarApart) }
        return .success(wanted)
    }

    /// The light multiplier that would make Readout agree with a reference meter. Lux is a
    /// ratio scale, so a correction here is a factor rather than a shift.
    static func lightMultiplier(
        measured: Double,
        reference: Double,
        currentMultiplier: Double
    ) -> Result<Double, Failure> {
        guard measured.isFinite, reference.isFinite, currentMultiplier.isFinite,
              measured > 0, reference > 0, currentMultiplier > 0
        else {
            return .failure(.notAReading)
        }
        let wanted = (currentMultiplier * reference / measured * 100).rounded() / 100
        guard lightMultiplierRange.contains(wanted) else { return .failure(.tooFarApart) }
        return .success(wanted)
    }

    /// A figure typed into the reference field, read the way the phone's region writes
    /// numbers — so "48,5" works where that is how a decimal is written.
    static func parse(_ text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A full stop is read as a decimal point even where the region groups digits with
        // it, as long as the region's own decimal separator is absent. Left to the locale,
        // "52.4" in Germany parses as 524 — a tenfold calibration error from one keystroke.
        let separator = locale.decimalSeparator ?? "."
        if separator != ".", trimmed.contains("."), !trimmed.contains(separator) {
            return Double(trimmed).flatMap { $0.isFinite ? $0 : nil }
        }
        if let value = try? Double(trimmed, format: .number.locale(locale)), value.isFinite {
            return value
        }
        guard let value = Double(trimmed), value.isFinite else { return nil }
        return value
    }
}
