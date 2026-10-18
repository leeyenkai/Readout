import Foundation

/// One reading at one moment. `values` is aligned with the reading's channels.
struct SensorSample: Sendable, Equatable {
    var time: Date
    var values: [Double]
    /// Set for discrete readings (proximity, thermal state) and used as the displayed text.
    var state: String?
    /// Short qualifier shown next to the value, for example "Charging" or "Estimated".
    var note: String?

    init(time: Date = .now, values: [Double] = [], state: String? = nil, note: String? = nil) {
        self.time = time
        self.values = values
        self.state = state
        self.note = note
    }

    /// Euclidean length of the first three channels, used for the single-value tile summary.
    var magnitude: Double {
        let components = values.prefix(3)
        return sqrt(components.reduce(0) { $0 + $1 * $1 })
    }

    func value(_ channel: Int) -> Double? {
        values.indices.contains(channel) ? values[channel] : nil
    }
}

/// Running minimum, maximum and mean for one channel since the last reset.
struct ChannelStats: Sendable, Equatable {
    var minimum: Double
    var maximum: Double
    var sum: Double
    var count: Int

    var mean: Double { count == 0 ? 0 : sum / Double(count) }

    init(first value: Double) {
        minimum = value
        maximum = value
        sum = value
        count = 1
    }

    mutating func add(_ value: Double) {
        minimum = Swift.min(minimum, value)
        maximum = Swift.max(maximum, value)
        sum += value
        count += 1
    }
}
