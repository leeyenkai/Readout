import Foundation
import Testing
@testable import Readout

@Suite("Sound and light estimates")
struct EstimateMathsTests {
    @Test("Full scale maps to the assumed reference level")
    func fullScaleIsTheReference() {
        #expect(SoundLevelMaths.decibels(rms: 1) == SoundLevelMaths.fullScaleReference)
    }

    @Test("A tenth of full scale is 20 dB quieter")
    func tenthOfFullScale() {
        let level = SoundLevelMaths.decibels(rms: 0.1)
        #expect(abs(level - (SoundLevelMaths.fullScaleReference - 20)) < 0.0001)
    }

    @Test("Silence reads the floor rather than minus infinity")
    func silence() {
        #expect(SoundLevelMaths.decibels(rms: 0) == SoundLevelMaths.floor)
    }

    @Test("The calibration offset shifts the whole scale")
    func calibrationOffset() {
        let base = SoundLevelMaths.decibels(rms: 0.01)
        let shifted = SoundLevelMaths.decibels(rms: 0.01, calibrationOffset: -6)
        #expect(abs((base - shifted) - 6) < 0.0001)
    }

    @Test("A longer time constant smooths more")
    func smoothing() {
        let fast = SoundLevelMaths.smoothing(timeConstant: 0.125, interval: 0.02)
        let slow = SoundLevelMaths.smoothing(timeConstant: 1, interval: 0.02)
        #expect(fast > slow)
        #expect(slow > 0 && fast < 1)
    }

    @Test("Exposure value follows the textbook definition")
    func exposureValue() {
        // f/1, 1 second, ISO 100 is EV 0 by definition.
        let ev = LightMaths.exposureValue(aperture: 1, exposureDuration: 1, iso: 100)
        #expect(ev == 0)

        // Halving the shutter time adds a stop.
        let faster = LightMaths.exposureValue(aperture: 1, exposureDuration: 0.5, iso: 100)
        #expect(faster == 1)

        // Doubling the ISO takes one away.
        let sensitive = LightMaths.exposureValue(aperture: 1, exposureDuration: 1, iso: 200)
        #expect(sensitive == -1)
    }

    @Test("Nonsense camera settings produce no reading rather than a wrong one")
    func invalidExposure() {
        #expect(LightMaths.exposureValue(aperture: 0, exposureDuration: 1, iso: 100) == nil)
        #expect(LightMaths.exposureValue(aperture: 1.8, exposureDuration: 0, iso: 100) == nil)
        #expect(LightMaths.exposureValue(aperture: 1.8, exposureDuration: 1, iso: 0) == nil)
    }

    @Test("Each stop of exposure doubles the lux")
    func luxDoubling() {
        let dim = LightMaths.lux(exposureValue: 5)
        let bright = LightMaths.lux(exposureValue: 6)
        #expect(abs(bright - dim * 2) < 0.0001)
        #expect(LightMaths.lux(exposureValue: 0) == LightMaths.calibrationConstant)
    }

    @Test("Calibration scales the estimate")
    func luxCalibration() {
        let base = LightMaths.lux(exposureValue: 8)
        let doubled = LightMaths.lux(exposureValue: 8, calibration: 2)
        #expect(abs(doubled - base * 2) < 0.0001)
    }
}
