import Foundation

/// The vertical scale of a live chart, which settles rather than jumping (R-25).
///
/// Fitting the axis to exactly what is on screen on every redraw made the whole trace leap
/// each time a new extreme arrived or an old one scrolled off the left — several times a
/// second for a noisy reading. This widens straight away, so nothing is ever drawn off the
/// chart, but narrows only once the data has sat well inside the band for a while, and always
/// lands on round gridline values.
struct ChartScale: Equatable, Sendable {
    private(set) var domain: ClosedRange<Double>?
    /// When the data first fitted comfortably in a smaller band, if it still does.
    private var narrowerSince: Date?

    /// How long the data must have fitted a smaller band before the axis shrinks to it.
    static let patience: TimeInterval = 2
    /// The share of the current band the data must have shrunk to before that counts.
    static let narrowingRatio = 0.6

    /// Takes the range of what is on screen now, and returns the domain to draw.
    @discardableResult
    mutating func update(lowest: Double, highest: Double, at now: Date) -> ClosedRange<Double> {
        let target = Self.niceDomain(lowest: lowest, highest: highest)
        guard let current = domain else {
            domain = target
            return target
        }
        if target.lowerBound < current.lowerBound || target.upperBound > current.upperBound {
            // Widen at once, but only as far as needed: the side that still fits stays put.
            let widened = min(current.lowerBound, target.lowerBound)...max(current.upperBound, target.upperBound)
            domain = widened
            narrowerSince = nil
            return widened
        }
        let currentSpan = current.upperBound - current.lowerBound
        let targetSpan = target.upperBound - target.lowerBound
        if targetSpan < currentSpan * Self.narrowingRatio {
            let since = narrowerSince ?? now
            narrowerSince = since
            if now.timeIntervalSince(since) >= Self.patience {
                domain = target
                narrowerSince = nil
                return target
            }
        } else {
            narrowerSince = nil
        }
        return current
    }

    mutating func reset() {
        domain = nil
        narrowerSince = nil
    }

    /// The band `lowest…highest` occupies, with a little room above and below, snapped out to
    /// round gridline values. A steady reading still gets a band, or the line would have
    /// nowhere to be drawn.
    static func niceDomain(lowest: Double, highest: Double) -> ClosedRange<Double> {
        guard lowest.isFinite, highest.isFinite, lowest <= highest else { return -1...1 }
        let span = highest - lowest
        let padding = span > 0 ? span * 0.15 : max(abs(highest) * 0.01, 0.5)
        let low = lowest - padding
        let high = highest + padding
        let step = niceStep(for: (high - low) / 4)
        guard step > 0, step.isFinite else { return low...high }
        let snappedLow = (low / step).rounded(.down) * step
        let snappedHigh = (high / step).rounded(.up) * step
        return snappedLow...max(snappedHigh, snappedLow + step)
    }

    /// 1, 2, 2.5 or 5 times a power of ten — the steps a person would label an axis with.
    static func niceStep(for rough: Double) -> Double {
        guard rough > 0, rough.isFinite else { return 1 }
        let magnitude = pow(10, (log10(rough)).rounded(.down))
        let fraction = rough / magnitude
        let nice: Double = switch fraction {
        case ..<1.5: 1
        case ..<2.25: 2
        case ..<3.5: 2.5
        case ..<7.5: 5
        default: 10
        }
        return nice * magnitude
    }
}
