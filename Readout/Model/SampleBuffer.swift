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
    /// Each channel's wrap, so an angle's statistics are worked out round the circle.
    let wraps: [AngleWrap?]
    private(set) var stats: [ChannelStats] = []
    private var storage: [SensorSample] = []
    private var nextIndex = 0

    init(capacity: Int = SampleBuffer.defaultCapacity, wraps: [AngleWrap?] = []) {
        self.capacity = capacity
        self.wraps = wraps
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

    /// Whether `append` would keep this sample. Asked first by an owner that is observed, so a
    /// sample the buffer is going to drop does not count as a change to it.
    func accepts(_ sample: SensorSample) -> Bool {
        guard let latest else { return true }
        return sample.time.timeIntervalSince(latest.time) >= Self.minimumInterval
    }

    /// Appends a sample unless one arrived less than `minimumInterval` ago.
    @discardableResult
    mutating func append(_ sample: SensorSample) -> Bool {
        guard accepts(sample) else { return false }
        if storage.count < capacity {
            storage.append(sample)
        } else {
            storage[nextIndex] = sample
            nextIndex = (nextIndex + 1) % capacity
        }
        record(sample)
        return true
    }

    /// The samples inside a window ending at `end`, oldest first.
    ///
    /// Walks the ring from the newest sample backwards and stops at the first one that falls
    /// outside the window, rather than materialising all 3,000 of them and filtering. The
    /// live chart calls this on every redraw — at display rate, for each of three axes — and
    /// copying the whole history each time to draw ten seconds of it was the most expensive
    /// thing the detail view did.
    ///
    /// Samples are appended in time order, so the first one outside the window means every
    /// one before it is too.
    func samples(in window: TimeInterval, endingAt end: Date = .now) -> [SensorSample] {
        guard !storage.isEmpty else { return [] }
        let start = end.addingTimeInterval(-window)
        let count = storage.count
        let isFull = count == capacity
        var collected: [SensorSample] = []
        collected.reserveCapacity(min(count, 256))

        for step in 1...count {
            // Newest first: the ring's last written slot, working backwards and wrapping.
            let index = isFull ? (nextIndex + count - step) % capacity : count - step
            let sample = storage[index]
            // The window is bounded at both ends. In practice `end` is now and nothing is
            // newer than that, but a window asked for in the past should not reach forwards
            // out of itself.
            guard sample.time <= end else { continue }
            guard sample.time >= start else { break }
            collected.append(sample)
        }
        return Array(collected.reversed())
    }

    /// Nil until the channel has had at least one finite value.
    func stats(channel: Int) -> ChannelStats? {
        guard stats.indices.contains(channel), !stats[channel].isEmpty else { return nil }
        return stats[channel]
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
            while !stats.indices.contains(index) {
                let channel = stats.count
                stats.append(ChannelStats(wrap: wraps.indices.contains(channel) ? wraps[channel] : nil))
            }
            stats[index].add(value)
        }
    }
}
