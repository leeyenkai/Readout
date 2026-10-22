import Foundation
import Testing
@testable import Readout

/// The bubble's direction, the edge a phone stands on, and Zero (R-32).
@Suite("Spirit level bubble and zero")
struct SpiritLevelTests {
    private func degrees(_ value: Double) -> Double { value * .pi / 180 }

    /// Core Motion's gravity, for a flat phone tipped by these angles. Raising an edge moves
    /// gravity away from it.
    private func flat(raisingRight right: Double = 0, raisingTop top: Double = 0) -> Vector3 {
        Vector3(x: -sin(degrees(right)), y: -sin(degrees(top)), z: -cos(degrees(right)) * cos(degrees(top)))
    }

    @Test("The bubble rises to whichever edge is raised")
    func bubbleRises() {
        // Right edge up: the bubble goes right.
        let right = LevelMaths.surfaceAngles(gravity: flat(raisingRight: 5))
        #expect(LevelMaths.bubbleOffset(x: right.x, y: right.y).x > 0)
        // Top edge up: the bubble goes up the screen, which is negative y.
        let top = LevelMaths.surfaceAngles(gravity: flat(raisingTop: 5))
        #expect(LevelMaths.bubbleOffset(x: top.x, y: top.y).y < 0)
        // Left edge up: left.
        let left = LevelMaths.surfaceAngles(gravity: flat(raisingRight: -5))
        #expect(LevelMaths.bubbleOffset(x: left.x, y: left.y).x < 0)
    }

    @Test("On an edge, the bubble runs to the high end")
    func edgeBubble() {
        // Turned clockwise: the right end drops, so the bubble runs left.
        let clockwise = Vector3(x: sin(degrees(4)), y: -cos(degrees(4)), z: 0)
        let angle = LevelMaths.edgeAngle(gravity: clockwise)
        #expect(angle > 0)
        #expect(LevelMaths.edgeBubbleOffset(angle: angle) < 0)
    }

    @Test("Standing on any of its four edges reads near zero, not ±90°", arguments: [
        (Vector3(x: 0, y: -1, z: 0), 0),
        (Vector3(x: 1, y: 0, z: 0), 1),
        (Vector3(x: 0, y: 1, z: 0), 2),
        (Vector3(x: -1, y: 0, z: 0), -1),
    ])
    func everyEdge(gravity: Vector3, quarterTurns: Int) {
        #expect(abs(LevelMaths.edgeAngle(gravity: gravity)) < 0.001)
        #expect(LevelMaths.edgeQuarterTurns(gravity: gravity) == quarterTurns)
    }

    @Test("Just either side of upside down reads a small angle, not nearly a full turn")
    func upsideDown() {
        let past = Vector3(x: -sin(degrees(2)), y: cos(degrees(2)), z: 0)
        let before = Vector3(x: sin(degrees(2)), y: cos(degrees(2)), z: 0)
        #expect(abs(LevelMaths.edgeAngle(gravity: past)) < 2.001)
        #expect(abs(LevelMaths.edgeAngle(gravity: before)) < 2.001)
        #expect(LevelMaths.edgeQuarterTurns(gravity: past) == 2)
        #expect(LevelMaths.edgeQuarterTurns(gravity: before) == 2)
    }

    @Test("Zeroing flat leaves the edges alone, and the other way round")
    func zerosAreSeparate() {
        var zero = LevelZero.none
        let tipped = flat(raisingRight: 1.5, raisingTop: -0.5)
        zero.zero(at: tipped)
        let surface = zero.surfaceAngles(gravity: tipped)
        #expect(abs(surface.x) < 0.001 && abs(surface.y) < 0.001)
        #expect(zero.isSurfaceZeroed)

        let leaning = Vector3(x: sin(degrees(3)), y: -cos(degrees(3)), z: 0)
        #expect(abs(zero.edgeAngle(gravity: leaning) - 3) < 0.001)

        zero.zero(at: leaning)
        #expect(abs(zero.edgeAngle(gravity: leaning)) < 0.001)
        // The flat zero is untouched by zeroing on an edge.
        #expect(abs(zero.surfaceAngles(gravity: tipped).x) < 0.001)
        // And another edge keeps its own.
        let onSide = Vector3(x: cos(degrees(3)), y: sin(degrees(3)), z: 0)
        #expect(abs(abs(zero.edgeAngle(gravity: onSide)) - 3) < 0.001)
    }

    @Test("Clearing removes only the zero for the mode the phone is in")
    func clearing() {
        var zero = LevelZero.none
        let tipped = flat(raisingRight: 2)
        let leaning = Vector3(x: sin(degrees(3)), y: -cos(degrees(3)), z: 0)
        zero.zero(at: tipped)
        zero.zero(at: leaning)
        zero.clear(at: leaning)
        #expect(!zero.isEdgeZeroed(quarterTurns: 0))
        #expect(zero.isSurfaceZeroed)
    }

    @Test("A zero survives being saved and read back")
    func zeroPersists() throws {
        var zero = LevelZero.none
        zero.zero(at: flat(raisingTop: 1))
        let data = try JSONEncoder().encode(zero)
        #expect(try JSONDecoder().decode(LevelZero.self, from: data) == zero)
    }
}
