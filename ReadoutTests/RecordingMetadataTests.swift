import Foundation
import Testing
@testable import Readout

@Suite("Recording metadata and names")
struct RecordingMetadataTests {
    private let start = Date(timeIntervalSince1970: 1_792_305_000)
    private static let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!

    // MARK: - Track summaries

    @Test("A track's summary carries min, max and mean per channel")
    func trackStatistics() throws {
        var builder = RecordedTrackBuilder(reading: .acceleration, fileName: "accel.csv")
        for (index, values) in [[0.1, -1.0, 0.0], [0.3, -0.8, 0.2], [0.2, -0.9, 0.1]].enumerated() {
            builder.add(SensorSample(time: start.addingTimeInterval(Double(index) * 0.1), values: values))
        }
        let track = builder.finish(byteCount: 512)

        #expect(track.sampleCount == 3)
        #expect(track.byteCount == 512)
        #expect(track.channels.count == 3)
        let x = try #require(track.channels.first)
        #expect(abs(x.minimum - 0.1) < 1e-9)
        #expect(abs(x.maximum - 0.3) < 1e-9)
        #expect(abs(x.mean - 0.2) < 1e-9)
        #expect(x.count == 3)
        #expect(track.reading == .acceleration)
    }

    @Test("A reading that starts reporting more channels mid-session still totals up")
    func growingChannelCount() throws {
        var builder = RecordedTrackBuilder(reading: .cadence, fileName: "cadence.csv")
        builder.add(SensorSample(time: start, values: [100]))
        builder.add(SensorSample(time: start.addingTimeInterval(1), values: [120, 500]))
        let track = builder.finish(byteCount: 64)
        #expect(track.sampleCount == 2)
        #expect(track.channels.count == 2)
        #expect(track.channels[0].minimum == 100)
        #expect(track.channels[0].maximum == 120)
        #expect(track.channels[1].count == 1)
    }

    @Test("An empty track has no channels and no samples")
    func emptyTrack() {
        let track = RecordedTrackBuilder(reading: .light, fileName: "light.csv").finish(byteCount: 32)
        #expect(track.sampleCount == 0)
        #expect(track.channels.isEmpty)
    }

    @Test("A track survives the JSON round trip a session is stored as")
    func trackEncoding() throws {
        var builder = RecordedTrackBuilder(reading: .soundLevel, fileName: "sound_level.csv")
        builder.add(SensorSample(time: start, values: [48]))
        let track = builder.finish(byteCount: 100)
        let data = try JSONEncoder().encode([track])
        let decoded = try JSONDecoder().decode([RecordedTrack].self, from: data)
        #expect(decoded == [track])
    }

    // MARK: - Names

    @Test("A session is named after when it ran and what it recorded (R-42)")
    func sessionNames() {
        #expect(RecordingNaming.name(when: "18 Oct 2026 at 14:30", readings: [.acceleration])
            == "18 Oct 2026 at 14:30 · Acceleration")
        #expect(RecordingNaming.name(when: "18 Oct 2026 at 14:30", readings: [.acceleration, .soundLevel])
            == "18 Oct 2026 at 14:30 · Acceleration, Sound level")
        #expect(RecordingNaming.name(when: "18 Oct 2026 at 14:30", readings: [])
            == "18 Oct 2026 at 14:30")
    }

    @Test("More readings than a row can show become \"and n more\"")
    func readingSummaries() {
        #expect(RecordingNaming.readingSummary([.acceleration]) == "Acceleration")
        #expect(RecordingNaming.readingSummary([.acceleration, .heading, .light, .battery])
            == "Acceleration, Heading and 2 more")
        #expect(RecordingNaming.readingSummary([.acceleration, .heading, .light], listing: 3)
            == "Acceleration, Heading, Light")
    }

    @Test("File names carry the date and time, because the share sheet drops the folder (R-44)")
    func fileNames() {
        #expect(RecordingNaming.fileName(prefix: "accel", startedAt: start, timeZone: Self.timeZone)
            == "Readout-2026-10-18-1430-accel.csv")
        #expect(RecordingNaming.fileName(prefix: "sound_level", startedAt: start, timeZone: Self.timeZone)
            == "Readout-2026-10-18-1430-sound_level.csv")
    }

    @Test("Elapsed time on the recording bar grows from m:ss to h:mm:ss")
    func elapsedText() {
        #expect(RecordingNaming.elapsedText(0) == "0:00")
        #expect(RecordingNaming.elapsedText(9.8) == "0:09")
        #expect(RecordingNaming.elapsedText(83) == "1:23")
        #expect(RecordingNaming.elapsedText(600) == "10:00")
        #expect(RecordingNaming.elapsedText(3_723) == "1:02:03")
        #expect(RecordingNaming.elapsedText(-1) == "0:00")
    }

    @Test("Sample counts read as English")
    func sampleCounts() {
        #expect(RecordingNaming.sampleCountText(1) == "1 sample")
        #expect(RecordingNaming.sampleCountText(0) == "0 samples")
        #expect(RecordingNaming.sampleCountText(12) == "12 samples")
    }

    // MARK: - Reading a session back

    @Test("A written table reads back with the same values")
    func csvRoundTrip() throws {
        let descriptor = ReadingCatalog.descriptor(.acceleration)
        let table = CSVTable(descriptor: descriptor, startedAt: start, timeZone: Self.timeZone)
        let values: [[Double]] = [[0.012, -0.981, 0.034], [0.015, -0.979, 0.031], [0.011, -0.983, 0.036]]
        let samples = values.enumerated().map { index, values in
            SensorSample(time: start.addingTimeInterval(Double(index) * 0.1), values: values)
        }
        let csv = ([table.header] + samples.map(table.row)).joined(separator: "\n") + "\n"

        let series = RecordedSeries(csv: csv)
        #expect(series.elapsed.count == 3)
        #expect(series.channels.count == 3)
        #expect(series.elapsed == [0, 0.1, 0.2])
        #expect(series.channels[0] == [0.012, 0.015, 0.011])
        #expect(series.channels[1] == [-0.981, -0.979, -0.983])
        let points = series.points(channel: 2)
        #expect(points.count == 3)
        #expect(points.last?.value == 0.036)
    }

    @Test("A header on its own reads back as an empty series")
    func headerOnly() {
        let descriptor = ReadingCatalog.descriptor(.soundLevel)
        let table = CSVTable(descriptor: descriptor, startedAt: start)
        #expect(RecordedSeries(csv: table.header + "\n").isEmpty)
        #expect(RecordedSeries(csv: "").isEmpty)
    }

    @Test("A row cut short by an interrupted recording is skipped, not fatal")
    func partialRowsAreSkipped() {
        let csv = """
        timestamp,elapsed_s,accel_x_g
        2026-10-18T14:30:00.000+08:00,0.000,0.012
        2026-10-18T14:30:00.100+08:00
        2026-10-18T14:30:00.200+08:00,0.200,0.011
        """
        let series = RecordedSeries(csv: csv)
        #expect(series.elapsed == [0, 0.2])
        #expect(series.channels[0] == [0.012, 0.011])
    }

    @Test("A long recording is thinned for the chart but keeps its shape")
    func downsampling() {
        let count = 10_000
        let series = RecordedSeries(
            elapsed: (0..<count).map { Double($0) * 0.02 },
            channels: [(0..<count).map { Double($0) }]
        )
        let points = series.points(channel: 0, limit: 400)
        #expect(points.count <= 400)
        #expect(points.count > 300)
        #expect(points.first?.value == 0)
        #expect(points.first?.elapsed == 0)
        #expect(series.points(channel: 3).isEmpty)
    }

    @Test("A missing value leaves a gap in the chart rather than a zero")
    func missingValuesAreNotPlotted() {
        let series = RecordedSeries(csv: """
        timestamp,elapsed_s,location_accuracy_horizontal_m,location_accuracy_vertical_m
        2026-10-18T14:30:00.000+08:00,0.000,6.5,
        2026-10-18T14:30:01.000+08:00,1.000,6.4,9.1
        """)
        #expect(series.points(channel: 1).count == 1)
        #expect(series.points(channel: 1).first?.value == 9.1)
        #expect(series.points(channel: 0).count == 2)
    }

    // MARK: - Session summaries

    @Test("A session's own summary adds up its tracks")
    func sessionSummary() {
        let tracks = [
            RecordedTrack(reading: .acceleration, fileName: "a.csv", sampleCount: 300, byteCount: 12_000, channels: []),
            RecordedTrack(reading: .soundLevel, fileName: "s.csv", sampleCount: 60, byteCount: 2_000, channels: []),
        ]
        let session = RecordingSession(
            identifier: UUID(),
            name: "Test",
            startedAt: start,
            duration: 30,
            rate: .high,
            isInterrupted: true,
            tracks: tracks
        )
        #expect(session.sampleCount == 360)
        #expect(session.byteCount == 14_000)
        #expect(session.tracks == tracks)
        #expect(session.readings == [.acceleration, .soundLevel])
        #expect(session.rate == .high)
        #expect(session.isInterrupted)
        #expect(session.endedAt == start.addingTimeInterval(30))
        #expect(session.listSummary.contains("2 readings"))
    }
}
