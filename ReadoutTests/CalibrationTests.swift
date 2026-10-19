import Foundation
import Testing
@testable import Readout

/// The arithmetic behind "hold a reference meter next to the phone and tell Readout what it
/// says" (R-10, R-66, Q-5). All of it is pure, so none of it needs a microphone or a camera.
@Suite("Calibration from a reference meter")
struct CalibrationTests {
    // MARK: - Sound

    @Test("A meter reading above Readout's raises the offset by the difference")
    func soundOffsetFromScratch() throws {
        let offset = try Calibration.soundOffset(measured: 48, reference: 52, currentOffset: 0).get()
        #expect(offset == 4)
    }

    @Test("The offset already in force is carried through, not measured twice")
    func soundOffsetCarriesTheCurrentOne() throws {
        // Readout reads 48 dB *with* a +4 offset already applied; the meter says 50, so the
        // correction wanted is +6 in total, not +2.
        let offset = try Calibration.soundOffset(measured: 48, reference: 50, currentOffset: 4).get()
        #expect(offset == 6)
    }

    @Test("Agreement leaves the offset where it is")
    func soundOffsetUnchanged() throws {
        let offset = try Calibration.soundOffset(measured: 61.2, reference: 61.2, currentOffset: -2.5).get()
        #expect(offset == -2.5)
    }

    @Test("The offset lands on half a decibel, which is as fine as the estimate gets")
    func soundOffsetRounding() throws {
        let offset = try Calibration.soundOffset(measured: 48, reference: 51.3, currentOffset: 0).get()
        #expect(offset == 3.5)
    }

    @Test("A correction bigger than the slider's range is refused rather than clamped")
    func soundOffsetTooFar() {
        #expect(Calibration.soundOffset(measured: 40, reference: 95, currentOffset: 0) == .failure(.tooFarApart))
        #expect(Calibration.soundOffset(measured: 95, reference: 40, currentOffset: 0) == .failure(.tooFarApart))
    }

    @Test("A correction right at the limit is still allowed")
    func soundOffsetAtTheLimit() throws {
        let offset = try Calibration.soundOffset(measured: 40, reference: 60, currentOffset: 0).get()
        #expect(offset == Calibration.soundOffsetRange.upperBound)
    }

    @Test("Nonsense is refused, and so is a reading of nothing")
    func soundOffsetRejectsNonsense() {
        #expect(Calibration.soundOffset(measured: .nan, reference: 50, currentOffset: 0) == .failure(.notAReading))
        #expect(Calibration.soundOffset(measured: 50, reference: .infinity, currentOffset: 0) == .failure(.notAReading))
        #expect(Calibration.soundOffset(measured: 50, reference: 0, currentOffset: 0) == .failure(.notAReading))
        #expect(Calibration.soundOffset(measured: 50, reference: -3, currentOffset: 0) == .failure(.notAReading))
    }

    // MARK: - Light

    @Test("A meter reading twice Readout's doubles the multiplier")
    func lightMultiplier() throws {
        let multiplier = try Calibration.lightMultiplier(measured: 250, reference: 500, currentMultiplier: 1).get()
        #expect(multiplier == 2)
    }

    @Test("The multiplier already in force is carried through")
    func lightMultiplierCarriesTheCurrentOne() throws {
        // 1.2 × (600 / 400) = 1.8
        let multiplier = try Calibration.lightMultiplier(measured: 400, reference: 600, currentMultiplier: 1.2).get()
        #expect(multiplier == 1.8)
    }

    @Test("Agreement leaves the multiplier where it is")
    func lightMultiplierUnchanged() throws {
        let multiplier = try Calibration.lightMultiplier(measured: 318, reference: 318, currentMultiplier: 0.75).get()
        #expect(multiplier == 0.75)
    }

    @Test("A multiplier outside the range Readout will apply is refused")
    func lightMultiplierTooFar() {
        #expect(Calibration.lightMultiplier(measured: 100, reference: 100_000, currentMultiplier: 1) == .failure(.tooFarApart))
        #expect(Calibration.lightMultiplier(measured: 100_000, reference: 100, currentMultiplier: 1) == .failure(.tooFarApart))
    }

    @Test("Lux is a ratio, so zero on either side is not a calibration")
    func lightMultiplierRejectsZero() {
        #expect(Calibration.lightMultiplier(measured: 0, reference: 300, currentMultiplier: 1) == .failure(.notAReading))
        #expect(Calibration.lightMultiplier(measured: 300, reference: 0, currentMultiplier: 1) == .failure(.notAReading))
        #expect(Calibration.lightMultiplier(measured: 300, reference: 300, currentMultiplier: 0) == .failure(.notAReading))
        #expect(Calibration.lightMultiplier(measured: .nan, reference: 300, currentMultiplier: 1) == .failure(.notAReading))
    }

    // MARK: - Reading what was typed

    @Test("A figure is read the way the phone's region writes numbers")
    func parsing() {
        #expect(Calibration.parse("52", locale: Locale(identifier: "en_GB")) == 52)
        #expect(Calibration.parse(" 52.4 ", locale: Locale(identifier: "en_GB")) == 52.4)
        #expect(Calibration.parse("52,4", locale: Locale(identifier: "de_DE")) == 52.4)
        // A keypad can produce a full stop whatever the region, so that still reads.
        #expect(Calibration.parse("52.4", locale: Locale(identifier: "de_DE")) == 52.4)
    }

    @Test("An empty or unreadable field is no figure at all")
    func parsingNothing() {
        #expect(Calibration.parse("", locale: Locale(identifier: "en_GB")) == nil)
        #expect(Calibration.parse("   ", locale: Locale(identifier: "en_GB")) == nil)
        #expect(Calibration.parse("loud", locale: Locale(identifier: "en_GB")) == nil)
    }
}

/// The stored side of a calibration: it is the user's own correction, kept on the device.
@MainActor
@Suite("Calibration settings")
struct CalibrationSettingsTests {
    @Test("Clearing puts both estimates back to no correction")
    func clearing() {
        let settings = AppSettings(defaults: throwawayDefaults())
        #expect(!settings.hasCalibration)

        settings.soundCalibrationOffset = -3.5
        settings.lightCalibration = 1.4
        #expect(settings.hasCalibration)

        settings.resetCalibration()
        #expect(settings.soundCalibrationOffset == 0)
        #expect(settings.lightCalibration == 1)
        #expect(!settings.hasCalibration)
    }

    @Test("A correction survives a new AppSettings reading the same defaults")
    func persistence() {
        let defaults = throwawayDefaults()
        let settings = AppSettings(defaults: defaults)
        settings.soundCalibrationOffset = 6.5
        settings.lightCalibration = 0.8

        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.soundCalibrationOffset == 6.5)
        #expect(reopened.lightCalibration == 0.8)
    }
}
