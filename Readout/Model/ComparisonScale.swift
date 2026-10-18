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

    /// The reference a value is closest to, used for the "that is about…" line.
    func nearest(to value: Double) -> Reference? {
        references.min { abs($0.value - value) < abs($1.value - value) }
    }
}
