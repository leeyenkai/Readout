import Foundation

/// The bar of everyday references under a reading's chart (R-27).
///
/// Reference values are in the channel's stored (metric) unit; the view converts them.
struct ComparisonScale: Sendable, Equatable {
    struct Reference: Sendable, Equatable, Identifiable {
        let value: Double
        let label: String
        /// Marks a threshold worth warning about, such as 85 dB.
        let caution: Bool

        var id: String { "\(value)-\(label)" }

        init(_ value: Double, _ label: String, caution: Bool = false) {
            self.value = value
            self.label = label
            self.caution = caution
        }
    }

    let references: [Reference]
    let span: ClosedRange<Double>
    /// Light spans five orders of magnitude, so its bar is logarithmic.
    let logarithmic: Bool

    init(references: [Reference], span: ClosedRange<Double>, logarithmic: Bool = false) {
        self.references = references
        self.span = span
        self.logarithmic = logarithmic
    }

    /// Where a value sits on the bar, clamped to 0...1.
    func position(of value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value, span.lowerBound), span.upperBound)
        if logarithmic {
            let low = log10(max(span.lowerBound, 0.01))
            let high = log10(span.upperBound)
            return (log10(max(clamped, 0.01)) - low) / (high - low)
        }
        return (clamped - span.lowerBound) / (span.upperBound - span.lowerBound)
    }

    /// The reference a value is closest to, used for the "that is about…" line — or nothing,
    /// when the value is not close to any of them.
    ///
    /// "About the same as" has to be earned. Returning the nearest reference whatever the gap
    /// had the battery reading call 50% "about the same as" the Low Power Mode prompt at 20%,
    /// and a phone sitting still "about the same as" a car pulling away, neither of which is
    /// true (P-2).
    ///
    /// Closeness is measured along the bar rather than in the reading's own unit, so one
    /// tolerance serves every scale: a span of 0–100,000 lux and a span of −30–30 metres are
    /// both a bar of the same width, and the logarithmic scales come out right without a
    /// second rule.
    func nearest(to value: Double) -> Reference? {
        guard value.isFinite else { return nil }
        let placed = position(of: value)
        let closest = references.min {
            abs(position(of: $0.value) - placed) < abs(position(of: $1.value) - placed)
        }
        guard let closest, abs(position(of: closest.value) - placed) <= Self.tolerance else {
            return nil
        }
        return closest
    }

    /// How far along the bar a value may sit from a reference and still be described by it.
    private static let tolerance = 0.05
}
