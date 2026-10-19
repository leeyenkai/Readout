import Foundation
import Testing
@testable import Readout

@Suite("Sample history and statistics")
struct SampleBufferTests {
    /// Samples spaced far enough apart to survive the buffer's decimation.
    private func samples(_ values: [Double], from start: Date = Date(timeIntervalSince1970: 0)) -> [SensorSample] {
        values.enumerated().map { index, value in
            SensorSample(time: start.addingTimeInterval(Double(index) * 0.1), values: [value])
        }
    }

    @Test("Samples arriving faster than 10 Hz are dropped")
    func decimation() {
        var buffer = SampleBuffer()
        let start = Date(timeIntervalSince1970: 0)
        let first = buffer.append(SensorSample(time: start, values: [1]))
        let tooSoon = buffer.append(SensorSample(time: start.addingTimeInterval(0.01), values: [2]))
        let later = buffer.append(SensorSample(time: start.addingTimeInterval(0.1), values: [3]))
        #expect(first)
        #expect(!tooSoon)
        #expect(later)
        #expect(buffer.samples.count == 2)
        #expect(buffer.latest?.values == [3])
    }

    @Test("The ring keeps the newest samples in order once it is full")
    func ringWrapsInOrder() {
        var buffer = SampleBuffer(capacity: 3)
        for sample in samples([1, 2, 3, 4, 5]) {
            buffer.append(sample)
        }
        #expect(buffer.samples.map { $0.values[0] } == [3, 4, 5])
        #expect(buffer.latest?.values == [5])
    }

    @Test("Statistics survive the ring dropping old samples")
    func statisticsOutliveTheRing() throws {
        var buffer = SampleBuffer(capacity: 2)
        for sample in samples([10, 2, 6, 4]) {
            buffer.append(sample)
        }
        let stats = try #require(buffer.stats(channel: 0))
        #expect(stats.minimum == 2)
        #expect(stats.maximum == 10)
        #expect(stats.count == 4)
        #expect(stats.mean == 5.5)
    }

    @Test("Resetting statistics keeps the chart's history")
    func resetKeepsHistory() throws {
        var buffer = SampleBuffer()
        for sample in samples([1, 9]) {
            buffer.append(sample)
        }
        buffer.resetStats()
        #expect(buffer.stats(channel: 0) == nil)
        #expect(buffer.samples.count == 2)

        buffer.append(SensorSample(time: Date(timeIntervalSince1970: 1), values: [4]))
        let stats = try #require(buffer.stats(channel: 0))
        #expect(stats.minimum == 4)
        #expect(stats.maximum == 4)
    }

    @Test("A window returns only the samples inside it")
    func window() {
        var buffer = SampleBuffer()
        let now = Date(timeIntervalSince1970: 1_000)
        for offset in stride(from: -5.0, through: 0, by: 0.5) {
            buffer.append(SensorSample(time: now.addingTimeInterval(offset), values: [offset]))
        }
        let recent = buffer.samples(in: 2, endingAt: now)
        #expect(recent.count == 5)
        #expect(recent.allSatisfy { $0.time >= now.addingTimeInterval(-2) })
    }

    @Test("Magnitude is the length of the first three channels")
    func magnitude() {
        let sample = SensorSample(values: [3, 4, 0])
        #expect(sample.magnitude == 5)
        #expect(SensorSample(values: [0, 0, 0]).magnitude == 0)
    }

    /// The pedometer only reports a pace once you are walking, so a reading's channel count
    /// can grow part way through. The sample where that happens used to be dropped for the
    /// channels already known, which left the live statistics disagreeing with the recorded
    /// ones for the same session.
    @Test("A sample that adds a channel still counts for the channels already there")
    func channelAppearingMidStream() {
        var buffer = SampleBuffer()
        let start = Date(timeIntervalSince1970: 1_000)
        _ = buffer.append(SensorSample(time: start, values: [10]))
        _ = buffer.append(SensorSample(time: start.addingTimeInterval(1), values: [20, 100]))

        let first = buffer.stats(channel: 0)
        #expect(first?.count == 2)
        #expect(first?.minimum == 10)
        #expect(first?.maximum == 20)

        let second = buffer.stats(channel: 1)
        #expect(second?.count == 1)
        #expect(second?.minimum == 100)
    }

    @Test("Asking for a channel that is not there gives nothing")
    func missingChannel() {
        let sample = SensorSample(values: [1])
        #expect(sample.value(0) == 1)
        #expect(sample.value(3) == nil)
    }
}
