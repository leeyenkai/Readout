import Foundation
import Testing
@testable import Readout

@Suite("Recording sample rates")
struct SampleRateGateTests {
    private let start = Date(timeIntervalSince1970: 0)

    /// Counts how many of a steady stream of samples a gate keeps over `seconds`.
    private func kept(
        rate: RecordingRate,
        cadence: RecordingCadence = .driven,
        streamHertz: Double,
        seconds: Double,
        jitter: Double = 0
    ) -> Int {
        var gate = SampleRateGate(rate: rate, cadence: cadence)
        var count = 0
        let step = 1 / streamHertz
        var index = 0
        while Double(index) * step < seconds {
            let offset = Double(index) * step + (index.isMultiple(of: 2) ? jitter : -jitter)
            if gate.accepts(start.addingTimeInterval(offset)) { count += 1 }
            index += 1
        }
        return count
    }

    @Test("Low keeps one sample a second out of a 10 Hz stream")
    func lowRate() {
        #expect(kept(rate: .low, streamHertz: 10, seconds: 10) == 10)
    }

    @Test("Medium keeps ten samples a second out of a 60 Hz stream")
    func mediumRate() {
        #expect(kept(rate: .medium, streamHertz: 60, seconds: 10) == 100)
    }

    @Test("High keeps fifty samples a second, even from the 60 Hz a chart asks for")
    func highRateFromDisplayRate() {
        // The naive "has an interval passed" rule would give 30 Hz here, because every other
        // 60 Hz sample is too early; keeping a grid of due times is what makes it 50.
        #expect(kept(rate: .high, streamHertz: 60, seconds: 10) == 500)
    }

    @Test("A sensor running at exactly the requested rate keeps everything, jitter and all")
    func jitterDoesNotDropSamples() {
        #expect(kept(rate: .high, streamHertz: 50, seconds: 10, jitter: 0.0005) == 500)
        #expect(kept(rate: .medium, streamHertz: 10, seconds: 10, jitter: 0.004) == 100)
    }

    @Test("Location, pressure and the pedometer keep every sample they are sent (R-39)")
    func freeCadenceKeepsEverything() {
        #expect(kept(rate: .low, cadence: .free, streamHertz: 10, seconds: 5) == 50)
        #expect(kept(rate: .high, cadence: .free, streamHertz: 1, seconds: 5) == 5)
    }

    @Test("A sensor slower than the chosen rate is never sped up")
    func slowSensorPassesThrough() {
        #expect(kept(rate: .high, streamHertz: 1, seconds: 5) == 5)
    }

    @Test("The first sample is always kept")
    func firstSampleKept() {
        var gate = SampleRateGate(rate: .low, cadence: .driven)
        let first = gate.accepts(start)
        let tooSoon = gate.accepts(start.addingTimeInterval(0.1))
        #expect(first)
        #expect(!tooSoon)
    }

    @Test("A gap in the stream restarts the grid rather than letting a burst through")
    func gapRestartsTheGrid() {
        var gate = SampleRateGate(interval: 1)
        let first = gate.accepts(start)
        let afterGap = gate.accepts(start.addingTimeInterval(10))
        // The next sample arrives a tenth of a second later: too soon, even though the grid
        // spent nine seconds waiting.
        let tooSoon = gate.accepts(start.addingTimeInterval(10.1))
        let onTime = gate.accepts(start.addingTimeInterval(11))
        #expect(first)
        #expect(afterGap)
        #expect(!tooSoon)
        #expect(onTime)
    }

    @Test("A zero interval keeps every sample, however close together")
    func zeroInterval() {
        var gate = SampleRateGate(interval: 0)
        let accepted = (0..<3).map { gate.accepts(start.addingTimeInterval(Double($0) * 0.001)) }
        #expect(accepted == [true, true, true])
    }

    @Test("Each rate maps to the hertz and activation the spec names (R-39, R-65)")
    func rateMapping() {
        #expect(RecordingRate.low.hertz == 1)
        #expect(RecordingRate.medium.hertz == 10)
        #expect(RecordingRate.high.hertz == 50)
        #expect(RecordingRate.low.activationRate == .standard)
        #expect(RecordingRate.medium.activationRate == .standard)
        #expect(RecordingRate.high.activationRate == .fast)
        #expect(RecordingRate.high.interval == 0.02)
    }

    @Test("Each reading is classified the way R-39 describes it")
    func cadenceByReading() {
        // Core Motion follows the rate it is asked for; the location, altimeter and pedometer
        // readings arrive when their framework says so; the rest are capped but not driven.
        let driven: Set<ReadingID> = [.acceleration, .rotationRate, .orientation, .magneticField]
        let free: Set<ReadingID> = [
            .heading, .airPressure, .relativeAltitude,
            .coordinates, .gpsAltitude, .speed, .course, .locationAccuracy,
            .activity, .cadence,
        ]
        for descriptor in ReadingCatalog.all {
            let expected: RecordingCadence
            if driven.contains(descriptor.id) {
                expected = .driven
            } else if free.contains(descriptor.id) {
                expected = .free
            } else {
                expected = .capped
            }
            #expect(descriptor.recordingCadence == expected, "\(descriptor.id.rawValue)")
        }
    }

    @Test("A reading with its own rate is still held to the chosen one")
    func cappedCadence() {
        // The microphone publishes at 10 Hz whatever is asked of it; a Low recording of it
        // should still be one sample a second.
        #expect(kept(rate: .low, cadence: .capped, streamHertz: 10, seconds: 10) == 10)
        #expect(kept(rate: .high, cadence: .capped, streamHertz: 10, seconds: 10) == 100)
    }

    /// Core Location replays its last fix every time a provider is started, and the hub starts
    /// one whenever another screen takes a lease. Those replays must not become extra rows.
    @Test("A sample that is not newer than the last one kept is never kept again", arguments: [
        RecordingCadence.free, .driven,
    ])
    func replayedSamplesAreDropped(cadence: RecordingCadence) {
        var gate = SampleRateGate(rate: .low, cadence: cadence)
        let fix = start.addingTimeInterval(5)
        let first = gate.accepts(fix)
        let replayed = gate.accepts(fix)
        let older = gate.accepts(fix.addingTimeInterval(-1))
        let later = gate.accepts(fix.addingTimeInterval(10))
        #expect(first)
        #expect(!replayed)
        #expect(!older)
        #expect(later)
    }
}
