import Foundation
import Testing
@testable import Readout

/// The live chart's vertical scale, which widens at once and narrows only once the data has
/// settled (R-25).
@Suite("Chart scale")
struct ChartScaleTests {
    private let start = Date(timeIntervalSince1970: 0)

    @Test("Gridlines land on round values", arguments: [
        (0.13, 0.1), (0.3, 0.25), (0.7, 0.5), (1.8, 2.0), (4, 5), (12, 10), (230, 250),
    ])
    func niceSteps(rough: Double, expected: Double) {
        #expect(abs(ChartScale.niceStep(for: rough) - expected) < 0.000_1)
    }

    @Test("The band covers the data with room to spare, on round values")
    func niceDomain() {
        let domain = ChartScale.niceDomain(lowest: 1_011.3, highest: 1_014.8)
        #expect(domain.lowerBound <= 1_011.3 && domain.upperBound >= 1_014.8)
        #expect(domain.lowerBound.truncatingRemainder(dividingBy: 0.5) == 0)
        // A steady reading still gets a band to be drawn in.
        let flat = ChartScale.niceDomain(lowest: 5, highest: 5)
        #expect(flat.lowerBound < 5 && flat.upperBound > 5)
    }

    @Test("A new extreme widens the scale straight away")
    func widensAtOnce() {
        var scale = ChartScale()
        let first = scale.update(lowest: 0, highest: 1, at: start)
        let wider = scale.update(lowest: 0, highest: 5, at: start.addingTimeInterval(0.1))
        #expect(wider.upperBound >= 5)
        #expect(wider.lowerBound <= first.lowerBound)
    }

    @Test("It narrows only once the data has sat in a smaller band for a while")
    func narrowsPatiently() {
        var scale = ChartScale()
        let wide = scale.update(lowest: -10, highest: 10, at: start)
        let soon = scale.update(lowest: -1, highest: 1, at: start.addingTimeInterval(0.5))
        #expect(soon == wide)
        let still = scale.update(lowest: -1, highest: 1, at: start.addingTimeInterval(1.5))
        #expect(still == wide)
        let later = scale.update(lowest: -1, highest: 1, at: start.addingTimeInterval(2.6))
        #expect(later.upperBound - later.lowerBound < wide.upperBound - wide.lowerBound)
    }

    @Test("Data that comes back out of the narrow band starts the wait again")
    func waitRestarts() {
        var scale = ChartScale()
        let wide = scale.update(lowest: -10, highest: 10, at: start)
        scale.update(lowest: -1, highest: 1, at: start.addingTimeInterval(1))
        scale.update(lowest: -9, highest: 9, at: start.addingTimeInterval(1.5))
        let after = scale.update(lowest: -1, highest: 1, at: start.addingTimeInterval(3.2))
        #expect(after == wide)
    }
}
