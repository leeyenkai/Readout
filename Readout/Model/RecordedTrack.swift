import Foundation

/// What a finished recording knows about one of its readings: which file holds the samples,
/// how many there are and the statistics the session view shows (R-43).
///
/// Statistics are kept in stored units, like everything else in the model, so the session
/// view can convert them with the user's current preferences.
struct RecordedTrack: Codable, Hashable, Sendable, Identifiable {
    var reading: ReadingID
    var fileName: String
    var sampleCount: Int
    var byteCount: Int
    var channels: [RecordedChannelSummary]

    var id: ReadingID { reading }

    var descriptor: ReadingDescriptor { ReadingCatalog.descriptor(reading) }
}

/// Minimum, maximum and mean of one channel over a whole session (R-43).
struct RecordedChannelSummary: Codable, Hashable, Sendable {
    var minimum: Double
    var maximum: Double
    var mean: Double
    var count: Int

    init(minimum: Double, maximum: Double, mean: Double, count: Int) {
        self.minimum = minimum
        self.maximum = maximum
        self.mean = mean
        self.count = count
    }

    init(_ stats: ChannelStats) {
        self.init(minimum: stats.minimum, maximum: stats.maximum, mean: stats.mean, count: stats.count)
    }
}

/// Accumulates one reading's statistics and row count while a recording runs, and turns them
/// into a `RecordedTrack` at the end.
///
/// Separate from the file writing so the metadata a session is saved with can be tested
/// without touching the disk.
struct RecordedTrackBuilder {
    let reading: ReadingID
    let fileName: String

    private(set) var sampleCount = 0
    private(set) var stats: [ChannelStats] = []

    init(reading: ReadingID, fileName: String) {
        self.reading = reading
        self.fileName = fileName
    }

    mutating func add(_ sample: SensorSample) {
        sampleCount += 1
        // A reading can start reporting a channel part way through a session — the pedometer
        // only has a pace once you are walking — so a new channel is taken up where it
        // appears, without losing the values of the ones already there.
        for (index, value) in sample.values.enumerated() {
            if stats.indices.contains(index) {
                stats[index].add(value)
            } else {
                stats.append(ChannelStats(first: value))
            }
        }
    }

    func finish(byteCount: Int) -> RecordedTrack {
        RecordedTrack(
            reading: reading,
            fileName: fileName,
            sampleCount: sampleCount,
            byteCount: byteCount,
            channels: stats.map(RecordedChannelSummary.init)
        )
    }
}
