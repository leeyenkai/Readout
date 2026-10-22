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
///
/// A value that is not finite is a sample with nothing to say for this channel — no course
/// while standing still, no altitude without a vertical fix — and is left out rather than
/// counted as zero, which would drag the average towards a value nobody measured.
///
/// A channel that wraps (`AngleWrap`) is summarised round the circle: the mean comes from the
/// summed sines and cosines, and each value is unwrapped next to the one before it, so the
/// minimum and maximum are the two ends of the arc the reading actually swept. Both stay
/// running totals, so nothing has to walk the sample history to produce them.
struct ChannelStats: Sendable, Equatable {
    let wrap: AngleWrap?
    private(set) var count = 0
    private var lowest = 0.0
    private var highest = 0.0
    private var sum = 0.0
    private var sineSum = 0.0
    private var cosineSum = 0.0
    /// The last value in unwrapped form, for a channel that wraps.
    private var previous: Double?

    init(wrap: AngleWrap? = nil) {
        self.wrap = wrap
    }

    var isEmpty: Bool { count == 0 }

    var minimum: Double {
        guard let wrap, coversWholeCircle == false else {
            return wrap?.lowerBound ?? lowest
        }
        return wrap.normalised(lowest)
    }

    var maximum: Double {
        guard let wrap, coversWholeCircle == false else {
            return wrap?.upperBound ?? highest
        }
        return wrap.normalised(highest)
    }

    var mean: Double {
        guard count > 0 else { return 0 }
        guard let wrap else { return sum / Double(count) }
        // Readings spread evenly round the whole dial have no direction to speak of; the
        // unwrapped average is as good an answer as any and, unlike atan2(0, 0), says so
        // consistently.
        guard abs(sineSum) > 1e-9 || abs(cosineSum) > 1e-9 else {
            return wrap.normalised(sum / Double(count))
        }
        return wrap.normalised(atan2(sineSum, cosineSum) * 180 / .pi)
    }

    private var coversWholeCircle: Bool { highest - lowest >= 360 }

    mutating func add(_ value: Double) {
        guard value.isFinite else { return }
        let unwrapped: Double
        if let wrap {
            let folded = wrap.normalised(value)
            // `drift` wants both angles inside one turn, so the previous value is folded back
            // before the step is measured; the step is then added to the unwrapped one.
            unwrapped = previous.map { $0 + CompassMaths.drift(from: wrap.normalised($0), to: folded) } ?? folded
            previous = unwrapped
            let radians = folded * .pi / 180
            sineSum += sin(radians)
            cosineSum += cos(radians)
        } else {
            unwrapped = value
        }
        if count == 0 {
            lowest = unwrapped
            highest = unwrapped
        } else {
            lowest = Swift.min(lowest, unwrapped)
            highest = Swift.max(highest, unwrapped)
        }
        sum += unwrapped
        count += 1
    }
}
