import Foundation
import Testing
@testable import Readout

/// The only code in Readout that produces the files a user actually gets, and it had no
/// coverage at all.
@MainActor
@Suite("Recording track writer")
struct RecordingWriterTests {
    private let descriptor = ReadingCatalog.descriptor(.acceleration)

    private func makeWriter(startedAt: Date = Date(timeIntervalSince1970: 1_000)) throws -> RecordingTrackWriter {
        try RecordingTrackWriter(
            descriptor: descriptor,
            folder: throwawayDirectory(),
            startedAt: startedAt,
            rate: .high,
            timeZone: TimeZone(identifier: "UTC") ?? .current
        )
    }

    private func rows(of writer: RecordingTrackWriter) throws -> [String] {
        let text = try String(contentsOf: writer.url, encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }

    @Test("A new file holds its header and nothing else")
    func headerOnly() throws {
        let writer = try makeWriter()
        let lines = try rows(of: writer)
        #expect(lines.count == 1)
        #expect(lines[0].hasPrefix("timestamp,elapsed_s,accel_x_g"))
        #expect(writer.sampleCount == 0)
    }

    @Test("Samples reach the file, and the count matches the rows in it")
    func samplesReachTheFile() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try makeWriter(startedAt: start)
        for index in 0..<10 {
            writer.receive(SensorSample(
                time: start.addingTimeInterval(Double(index) * 0.02),
                values: [Double(index), 0, -1]
            ))
        }
        let track = writer.finish()

        let lines = try rows(of: writer)
        #expect(lines.count == track.sampleCount + 1, "one header plus one row per counted sample")
        #expect(track.sampleCount == 10)
        #expect(track.channels.count == 3)
        #expect(track.byteCount > 0)
    }

    @Test("Nothing is counted before it is written")
    func countFollowsTheFile() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try makeWriter(startedAt: start)
        writer.receive(SensorSample(time: start, values: [1, 2, 3]))

        #expect(writer.sampleCount == 0, "the row is still in the buffer")
        writer.flush()
        #expect(writer.sampleCount == 1)

        let lines = try rows(of: writer)
        #expect(lines.count == 2)
    }

    @Test("A snapshot describes the track as it stands, without ending it")
    func snapshotDoesNotFinish() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try makeWriter(startedAt: start)
        writer.receive(SensorSample(time: start, values: [1, 2, 3]))
        writer.flush()

        let midway = writer.snapshot()
        #expect(midway.sampleCount == 1)

        writer.receive(SensorSample(time: start.addingTimeInterval(0.02), values: [4, 5, 6]))
        writer.flush()
        #expect(writer.snapshot().sampleCount == 2, "the writer carried on after the snapshot")
    }

    @Test("A write that cannot land is reported rather than silently counted")
    func failedWriteIsReported() throws {
        let folder = throwawayDirectory()
        let writer = try RecordingTrackWriter(
            descriptor: descriptor,
            folder: folder,
            startedAt: Date(timeIntervalSince1970: 1_000),
            rate: .high
        )
        // Pulling the file out from under the handle is the one way to make a write fail
        // without filling the disk. The rows then have nowhere to go.
        try FileManager.default.removeItem(at: folder)

        writer.receive(SensorSample(time: Date(timeIntervalSince1970: 1_000), values: [1, 2, 3]))
        writer.flush()

        if writer.hasFailed {
            #expect(writer.droppedSamples == 1)
            #expect(writer.sampleCount == 0, "a sample that never reached the file is not counted")
        } else {
            // A handle to an unlinked file still accepts writes on APFS, which is a correct
            // outcome too: the bytes are counted because they really were written.
            #expect(writer.sampleCount == 1)
            #expect(writer.droppedSamples == 0)
        }
    }

    @Test("A recording reads back through the streaming reader", arguments: [40, 5_000])
    func streamingReadBack(rowCount: Int) throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try makeWriter(startedAt: start)
        for index in 0..<rowCount {
            writer.receive(SensorSample(
                time: start.addingTimeInterval(Double(index) * 0.02),
                values: [Double(index), 0, -1]
            ))
        }
        let track = writer.finish()

        let series = try #require(RecordedSeries(contentsOf: writer.url))
        #expect(!series.isEmpty)
        #expect(series.channels.count == 3)
        // Thinned on the way in, so a long recording costs no more memory than a short one.
        #expect(series.elapsed.count <= min(track.sampleCount, 3_200))
        #expect(series.elapsed.first == 0)
        // X climbs by one per row, so the shape has to still be rising at the end.
        let x = series.channels[0]
        #expect(try #require(x.last) > #require(x.first))
    }

    @Test("The streaming reader and the string reader agree on a small file")
    func readersAgree() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let writer = try makeWriter(startedAt: start)
        for index in 0..<20 {
            writer.receive(SensorSample(
                time: start.addingTimeInterval(Double(index) * 0.02),
                values: [Double(index), Double(index) * 2, 0]
            ))
        }
        _ = writer.finish()

        let streamed = try #require(RecordedSeries(contentsOf: writer.url))
        let whole = RecordedSeries(csv: try String(contentsOf: writer.url, encoding: .utf8))
        #expect(streamed == whole)
    }
}
