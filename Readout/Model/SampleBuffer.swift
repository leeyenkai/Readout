import Foundation

/// A fixed-size history of samples plus running statistics.
///
/// Sensors can deliver at display rate, which is more than any chart needs, so the buffer
/// decimates to `minimumInterval` (about 10 Hz). Statistics see every decimated sample and
/// survive the ring dropping old ones, because they are kept as running totals (R-26).
struct SampleBuffer: Sendable {
    /// 5 minutes at 10 Hz — the longest chart window in the detail view (R-25).
    static let defaultCapacity = 3_000
    static let minimumInterval: TimeInterval = 0.095

    let capacity: Int
    private(set) var stats: [ChannelStats] = []
    private var storage: [SensorSample] = []
    private var nextIndex = 0

    init(capacity: Int = SampleBuffer.defaultCapacity) {
        self.capacity = capacity
        storage.reserveCapacity(min(capacity, 512))
    }

    /// Samples oldest first.
    var samples: [SensorSample] {
        guard storage.count == capacity else { return storage }
        return Array(storage[nextIndex...] + storage[..<nextIndex])
    }

    var latest: SensorSample? {
        guard !storage.isEmpty else { return nil }
        let index = storage.count == capacity ? (nextIndex + capacity - 1) % capacity : storage.count - 1
        return storage[index]
    }

    var isEmpty: Bool { storage.isEmpty }

    /// Appends a sample unless one arrived less than `minimumInterval` ago.
    @discardableResult
    mutating func append(_ sample: SensorSample) -> Bool {
        if let latest, sample.time.timeIntervalSince(latest.time) < Self.minimumInterval {
            return false
        }
        if storage.count < capacity {
            storage.append(sample)
        } else {
            storage[nextIndex] = sample
            nextIndex = (nextIndex + 1) % capacity
        }
        record(sample)
        return true
    }

    func samples(in window: TimeInterval, endingAt end: Date = .now) -> [SensorSample] {
        let start = end.addingTimeInterval(-window)
        return samples.filter { $0.time >= start }
    }

    func stats(channel: Int) -> ChannelStats? {
        stats.indices.contains(channel) ? stats[channel] : nil
    }

    /// Clears the statistics but keeps the history, so the chart does not jump (R-26).
    mutating func resetStats() {
        stats = []
    }

    mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        nextIndex = 0
        stats = []
    }

    private mutating func record(_ sample: SensorSample) {
        // A reading can start reporting a channel part way through — the pedometer only has
        // a pace once you are walking. The new channel starts here, and the ones already
        // known still take this sample's value; taking the new channel and returning early
        // used to drop them, so the live statistics disagreed with the recorded ones.
        for (index, value) in sample.values.enumerated() {
            if stats.indices.contains(index) {
                stats[index].add(value)
            } else {
                stats.append(ChannelStats(first: value))
            }
        }
    }
}
