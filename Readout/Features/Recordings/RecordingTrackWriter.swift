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
    private var handle: FileHandle
    private(set) var byteCount = 0
    /// Set if the disk refused a write. The session is still saved, with whatever reached it.
    private(set) var hasFailed = false

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
        builder.add(sample)
        buffer += table.row(sample) + "\n"
        if buffer.utf8.count >= Self.bufferLimit {
            flush()
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        let data = Data(buffer.utf8)
        buffer.removeAll(keepingCapacity: true)
        do {
            try handle.write(contentsOf: data)
            byteCount += data.count
        } catch {
            hasFailed = true
        }
    }

    func finish() -> RecordedTrack {
        flush()
        try? handle.close()
        return builder.finish(byteCount: byteCount)
    }
}
