import Foundation
import Testing
@testable import Readout

/// The compass's angle arithmetic (R-33, R-51).
@Suite("Compass maths")
struct CompassMathsTests {
    /// The haptic used to follow the *nearest* cardinal point, which changes as the heading
    /// crosses 45°, 135°, 225° and 315° — so the tap meant to mark north was felt exactly
    /// halfway between north and east.
    @Test("The tick lands on the cardinal point, not halfway to the next one")
    func crossingIsNotNearest() {
        #expect(CompassMaths.cardinalCrossing(heading: 0) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 90) == 1)
        #expect(CompassMaths.cardinalCrossing(heading: 180) == 2)
        #expect(CompassMaths.cardinalCrossing(heading: 270) == 3)

        // Halfway between two points is no point at all.
        #expect(CompassMaths.cardinalCrossing(heading: 45) == nil)
        #expect(CompassMaths.cardinalCrossing(heading: 135) == nil)
        #expect(CompassMaths.cardinalCrossing(heading: 225) == nil)
        #expect(CompassMaths.cardinalCrossing(heading: 315) == nil)
        #expect(CompassMaths.cardinalCrossing(heading: 30) == nil)
    }

    @Test("A dial sitting just off a point is still on it")
    func toleranceAroundAPoint() {
        #expect(CompassMaths.cardinalCrossing(heading: 1.5) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 358.5) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 91.9) == 1)
        #expect(CompassMaths.cardinalCrossing(heading: 94) == nil)
    }

    /// Passing north from 359° to 1° is one crossing, so the index must not change in the
    /// middle of it and fire a second tap.
    @Test("Passing north is one crossing, not two")
    func northIsOneCrossing() {
        #expect(CompassMaths.cardinalCrossing(heading: 359) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 360) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 1) == 0)
    }

    @Test("A heading outside nought to 360 is folded back onto the dial")
    func normalisation() {
        #expect(CompassMaths.normalised(370) == 10)
        #expect(CompassMaths.normalised(-10) == 350)
        #expect(CompassMaths.normalised(0) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: -1) == 0)
        #expect(CompassMaths.cardinalCrossing(heading: 450) == 1)
    }

    @Test("Nothing is on a point when there is no heading to speak of")
    func nonFiniteHeading() {
        #expect(CompassMaths.cardinalCrossing(heading: .nan) == nil)
        #expect(CompassMaths.cardinalCrossing(heading: .infinity) == nil)
    }

    // MARK: - Drift from a locked bearing

    @Test("Drift is signed and never more than half a turn either way")
    func drift() {
        #expect(CompassMaths.drift(from: 90, to: 100) == 10)
        #expect(CompassMaths.drift(from: 90, to: 80) == -10)
        #expect(CompassMaths.drift(from: 0, to: 0) == 0)

        // The short way round, not the long one.
        #expect(CompassMaths.drift(from: 350, to: 10) == 20)
        #expect(CompassMaths.drift(from: 10, to: 350) == -20)

        for bearing in stride(from: 0.0, to: 360, by: 15) {
            for heading in stride(from: 0.0, to: 360, by: 15) {
                let drift = CompassMaths.drift(from: bearing, to: heading)
                #expect(drift > -180.0001 && drift <= 180.0001)
            }
        }
    }

    @Test("No bearing means no drift rather than a nonsense angle")
    func driftWithoutAHeading() {
        #expect(CompassMaths.drift(from: .nan, to: 90) == 0)
        #expect(CompassMaths.drift(from: 90, to: .nan) == 0)
    }
}
