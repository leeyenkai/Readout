import Foundation
import Testing
@testable import Readout

/// Statistics for angles that wrap round the circle, and for samples with a channel missing
/// (P-2, R-26, R-43).
@Suite("Angle and missing-value statistics")
struct AngleStatisticsTests {
    private func stats(_ values: [Double], wrap: AngleWrap?) -> ChannelStats {
        var stats = ChannelStats(wrap: wrap)
        values.forEach { stats.add($0) }
        return stats
    }

    @Test("A heading jittering either side of north averages to north, not south")
    func headingAcrossNorth() {
        let heading = stats([358, 2, 359, 1, 0], wrap: .fullTurn)
        #expect(heading.mean < 0.5 || heading.mean > 359.5)
        #expect(abs(heading.minimum - 358) < 0.001)
        #expect(abs(heading.maximum - 2) < 0.001)
        #expect(heading.count == 5)
    }

    @Test("Yaw either side of ±180° averages to 180°")
    func yawAcrossTheSeam() {
        let yaw = stats([179, -179, 178, -178], wrap: .halfTurn)
        #expect(abs(abs(yaw.mean) - 180) < 0.5)
        #expect(abs(yaw.minimum - 178) < 0.001)
        #expect(abs(yaw.maximum - -178) < 0.001)
    }

    @Test("Away from the seam an angle summarises like any other number")
    func ordinaryAngles() {
        let course = stats([80, 90, 100], wrap: .fullTurn)
        #expect(abs(course.mean - 90) < 0.001)
        #expect(abs(course.minimum - 80) < 0.001)
        #expect(abs(course.maximum - 100) < 0.001)
    }

    @Test("Turning all the way round reports the whole circle")
    func wholeCircle() {
        let spin = stats(Array(stride(from: 0.0, through: 400, by: 10)), wrap: .fullTurn)
        #expect(spin.minimum == 0)
        #expect(spin.maximum == 360)
    }

    @Test("Missing values are left out rather than counted as zero")
    func missingValuesAreSkipped() {
        let speed = stats([.nan, 2, .infinity, 4], wrap: nil)
        #expect(speed.count == 2)
        #expect(speed.mean == 3)
        #expect(speed.minimum == 2)
        #expect(speed.maximum == 4)
    }

    @Test("A channel that never had a value has no statistics")
    func emptyChannel() throws {
        var buffer = SampleBuffer()
        buffer.append(SensorSample(time: .now, values: [.nan]))
        #expect(buffer.stats(channel: 0) == nil)

        var builder = RecordedTrackBuilder(reading: .course, fileName: "course.csv")
        builder.add(SensorSample(values: [.nan]))
        let summary = try #require(builder.finish(byteCount: 0).channels.first)
        // Saved as zeros with no count, because the summary is JSON and JSON has no NaN.
        #expect(summary.count == 0)
        #expect(summary.mean == 0)
    }

    @Test("The catalog marks heading, course, roll and yaw as angles that wrap")
    func catalogWraps() {
        #expect(ReadingCatalog.descriptor(.heading).channelWraps == [.fullTurn])
        #expect(ReadingCatalog.descriptor(.course).channelWraps == [.fullTurn])
        #expect(ReadingCatalog.descriptor(.orientation).channelWraps == [nil, .halfTurn, .halfTurn])
        #expect(ReadingCatalog.descriptor(.acceleration).channelWraps == [nil, nil, nil])
    }

    @Test("A recording summarises a heading round the circle too")
    func recordedHeading() throws {
        var builder = RecordedTrackBuilder(reading: .heading, fileName: "heading.csv")
        for value in [357.0, 3, 359, 1] {
            builder.add(SensorSample(values: [value]))
        }
        let summary = try #require(builder.finish(byteCount: 0).channels.first)
        #expect(summary.mean < 1 || summary.mean > 359)
        #expect(abs(summary.minimum - 357) < 0.001)
        #expect(abs(summary.maximum - 3) < 0.001)
    }

    @Test("Folding an angle into its range", arguments: [
        (AngleWrap.fullTurn, 370.0, 10.0), (.fullTurn, -10, 350), (.halfTurn, 190, -170), (.halfTurn, -190, 170),
    ])
    func folding(wrap: AngleWrap, input: Double, expected: Double) {
        #expect(abs(wrap.normalised(input) - expected) < 0.000_1)
    }
}
