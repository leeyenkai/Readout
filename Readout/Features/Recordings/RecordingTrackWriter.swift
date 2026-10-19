import Foundation

/// Writes one reading's samples to its CSV file while a recording runs (R-44, R-45).
///
/// Rows are buffered and written in blocks, so a 50 Hz recording touches the file system
/// about once a second rather than fifty times. The buffer is flushed on the service's tick
/// and again when the recording stops, so a session that ends abruptly still has its rows.
@MainActor
final class RecordingTrackWriter {
    let reading: ReadingID
    let url: URL

    private let table: CSVTable
    private var builder: RecordedTrackBuilder
    private var gate: SampleRateGate
    private var buffer = ""
    /// The samples behind the rows sitting in `buffer`. They only reach the statistics once
    /// their rows reach the file, so a refused write cannot leave the saved metadata claiming
    /// more samples than the CSV actually holds.
    private var pending: [SensorSample] = []
    private var handle: FileHandle
    private(set) var byteCount = 0
    /// Set if the disk refused a write. The session is still saved, with whatever reached it.
    private(set) var hasFailed = false
    /// Rows the disk refused, reported to the user rather than quietly forgotten.
    private(set) var droppedSamples = 0

    /// About 16 KB of rows before a write.
    private static let bufferLimit = 16_384

    init(
        descriptor: ReadingDescriptor,
        folder: URL,
        startedAt: Date,
        rate: RecordingRate,
        timeZone: TimeZone = .current
    ) throws {
        reading = descriptor.id
        table = CSVTable(descriptor: descriptor, startedAt: startedAt, timeZone: timeZone)
        gate = SampleRateGate(rate: rate, cadence: descriptor.recordingCadence)
        let fileName = RecordingNaming.fileName(
            prefix: descriptor.csvPrefix,
            startedAt: startedAt,
            timeZone: timeZone
        )
        builder = RecordedTrackBuilder(reading: descriptor.id, fileName: fileName)
        url = folder.appending(path: fileName)
        let header = Data((table.header + "\n").utf8)
        try header.write(to: url, options: .atomic)
        handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        byteCount = header.count
    }

    var sampleCount: Int { builder.sampleCount }

    /// Keeps a sample if it lands on the chosen rate's grid (R-39).
    func receive(_ sample: SensorSample) {
        guard gate.accepts(sample.time) else { return }
        pending.append(sample)
        buffer += table.row(sample) + "\n"
        if buffer.utf8.count >= Self.bufferLimit {
            flush()
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let data = Data(buffer.utf8)
        let samples = pending
        buffer.removeAll(keepingCapacity: true)
        pending.removeAll(keepingCapacity: true)
        do {
            try handle.write(contentsOf: data)
            byteCount += data.count
            for sample in samples {
                builder.add(sample)
            }
        } catch {
            hasFailed = true
            droppedSamples += samples.count
        }
    }

    func finish() -> RecordedTrack {
        flush()
        // Rows sitting in the page cache are lost to a panic or a hard reset; a recording is
        // worth the one synchronous flush it takes to make it durable.
        try? handle.synchronize()
        try? handle.close()
        return builder.finish(byteCount: byteCount)
    }

    /// The track as it stands, for the checkpoint a crash would be recovered from.
    func snapshot() -> RecordedTrack {
        builder.finish(byteCount: byteCount)
    }
}
