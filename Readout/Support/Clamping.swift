import Foundation

extension Comparable {
    /// Keeps a value inside a range, for the bubble and the comparison bar, both of which
    /// have to stay on screen whatever the sensor reports.
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
