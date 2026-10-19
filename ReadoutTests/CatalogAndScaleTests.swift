import Foundation
import Testing
@testable import Readout

@Suite("Reading catalog")
struct ReadingCatalogTests {
    @Test("Every reading in the app has a descriptor")
    func everyReadingIsDescribed() {
        for reading in ReadingID.allCases {
            let descriptor = ReadingCatalog.descriptor(reading)
            #expect(descriptor.id == reading)
            #expect(!descriptor.name.isEmpty)
            #expect(!descriptor.source.isEmpty)
            #expect(!descriptor.channels.isEmpty)
        }
    }

    @Test("The catalog holds the 19 readings of v1, with no duplicates")
    func catalogSize() {
        #expect(ReadingCatalog.all.count == 19)
        #expect(Set(ReadingCatalog.all.map(\.id)).count == 19)
    }

    @Test("Every group has readings, and they add up to the whole catalog")
    func groupsPartitionTheCatalog() {
        let grouped = ReadingGroup.allCases.flatMap(ReadingCatalog.readings(in:))
        #expect(grouped.count == ReadingCatalog.all.count)
        for group in ReadingGroup.allCases {
            #expect(!ReadingCatalog.readings(in: group).isEmpty)
        }
    }

    @Test("Every reading explains itself")
    func explainersAreWritten() {
        for descriptor in ReadingCatalog.all {
            #expect(!descriptor.explainer.what.isEmpty)
            #expect(!descriptor.explainer.precision.isEmpty)
            #expect(!descriptor.explainer.tryThis.isEmpty)
        }
    }

    @Test("The camera, the microphone and the proximity sensor wait to be asked")
    func intrusiveSensorsAreOnDemand() {
        // Nothing that lights an indicator or blanks the screen may start with the grid
        // (R-19, R-68).
        #expect(ReadingCatalog.descriptor(.light).activation == .onDemand)
        #expect(ReadingCatalog.descriptor(.soundLevel).activation == .onDemand)
        #expect(ReadingCatalog.descriptor(.proximity).activation == .onDemand)
        #expect(ReadingCatalog.descriptor(.proximity).requiresExplicitStart)
        #expect(!ReadingCatalog.descriptor(.acceleration).requiresExplicitStart)
    }

    @Test("Estimates say so, and sensor readings do not")
    func estimatesAreLabelled() {
        #expect(ReadingCatalog.descriptor(.light).estimateNote != nil)
        #expect(ReadingCatalog.descriptor(.soundLevel).estimateNote != nil)
        #expect(ReadingCatalog.descriptor(.airPressure).estimateNote == nil)
    }

    @Test("Three-axis readings summarise as a magnitude on their tile")
    func axisReadingsSummarise() {
        let acceleration = ReadingCatalog.descriptor(.acceleration)
        #expect(acceleration.isMultiAxis)
        #expect(acceleration.summaryValue(SensorSample(values: [3, 4, 0])) == 5)

        let pressure = ReadingCatalog.descriptor(.airPressure)
        #expect(!pressure.isMultiAxis)
        #expect(pressure.summaryValue(SensorSample(values: [1_013])) == 1_013)
    }
}

@Suite("Comparison scales")
struct ComparisonScaleTests {
    @Test("A value sits proportionally along a linear scale")
    func linearPosition() {
        let scale = ComparisonScale(references: [.init(50, "Middle")], span: 0...100)
        #expect(scale.position(of: 0) == 0)
        #expect(scale.position(of: 50) == 0.5)
        #expect(scale.position(of: 100) == 1)
    }

    @Test("Values outside the scale are clamped rather than running off the bar")
    func clamping() {
        let scale = ComparisonScale(references: [], span: 0...100)
        #expect(scale.position(of: -500) == 0)
        #expect(scale.position(of: 5_000) == 1)
        #expect(scale.position(of: .nan) == 0)
    }

    @Test("Light uses a logarithmic bar, so a dim room is not pinned to zero")
    func logarithmicPosition() throws {
        let scale = try #require(ReadingCatalog.descriptor(.light).comparisons)
        #expect(scale.logarithmic)
        let livingRoom = scale.position(of: 50)
        let office = scale.position(of: 400)
        #expect(livingRoom > 0.3 && livingRoom < 0.7)
        #expect(office > livingRoom)
        #expect(scale.position(of: 100_000) == 1)
    }

    @Test("The nearest reference is the one the comparison line names")
    func nearestReference() throws {
        let scale = try #require(ReadingCatalog.descriptor(.soundLevel).comparisons)
        #expect(scale.nearest(to: 61)?.label == "Conversation")
        #expect(scale.nearest(to: 86)?.label == "Heavy traffic")
        #expect(scale.nearest(to: 86)?.caution == true)
    }
}

@Suite("Spirit level geometry")
struct LevelMathsTests {
    @Test("A phone lying flat is in surface mode and reads level")
    func flatPhone() {
        let gravity = Vector3(x: 0, y: 0, z: -1)
        #expect(LevelMaths.isSurfaceMode(gravity: gravity))
        let angles = LevelMaths.surfaceAngles(gravity: gravity)
        #expect(abs(angles.x) < 0.001)
        #expect(abs(angles.y) < 0.001)
        #expect(abs(LevelMaths.surfaceTilt(gravity: gravity)) < 0.001)
    }

    @Test("A phone standing upright switches to edge mode")
    func uprightPhone() {
        let gravity = Vector3(x: 0, y: -1, z: 0)
        #expect(!LevelMaths.isSurfaceMode(gravity: gravity))
        #expect(abs(LevelMaths.edgeAngle(gravity: gravity)) < 0.001)
    }

    @Test("Tilting an upright phone shows the angle it leans by")
    func leaningPhone() {
        let radians = 10.0 * .pi / 180
        let gravity = Vector3(x: sin(radians), y: -cos(radians), z: 0)
        #expect(abs(LevelMaths.edgeAngle(gravity: gravity) - 10) < 0.001)
    }

    @Test("A tilted flat phone reports the tilt on each axis")
    func tiltedFlatPhone() {
        let radians = 5.0 * .pi / 180
        let gravity = Vector3(x: sin(radians), y: 0, z: -cos(radians))
        let angles = LevelMaths.surfaceAngles(gravity: gravity)
        #expect(abs(angles.x - 5) < 0.001)
        #expect(abs(angles.y) < 0.001)
        #expect(abs(LevelMaths.surfaceTilt(gravity: gravity) - 5) < 0.001)
    }

    @Test("The bubble stays inside its circle, diagonals included")
    func bubbleStaysInside() {
        #expect(LevelMaths.bubblePosition(x: 0, y: 0) == (x: 0, y: 0))

        // Half of full scale on one axis is halfway out.
        let halfway = LevelMaths.bubblePosition(x: 7.5, y: 0)
        #expect(abs(halfway.x - 0.5) < 0.001)
        #expect(halfway.y == 0)

        // Full scale on both axes is √2 from the middle if each axis is clamped on its own;
        // as a vector it is pulled back to the rim and keeps its direction.
        let corner = LevelMaths.bubblePosition(x: 15, y: 15)
        #expect(abs(sqrt(corner.x * corner.x + corner.y * corner.y) - 1) < 0.001)
        #expect(abs(corner.x - corner.y) < 0.001)

        // However far the phone is tilted, the bubble never leaves the circle.
        let extreme = LevelMaths.bubblePosition(x: 90, y: -90)
        #expect(abs(sqrt(extreme.x * extreme.x + extreme.y * extreme.y) - 1) < 0.001)
        #expect(extreme.y < 0)
    }

    @Test("Gravity rebuilt from pitch and roll matches the real thing")
    func gravityFromAttitude() {
        let flat = LevelMaths.gravity(pitchDegrees: 0, rollDegrees: 0)
        #expect(abs(flat.z - -1) < 0.001)
        #expect(abs(flat.x) < 0.001)

        let upright = LevelMaths.gravity(pitchDegrees: 90, rollDegrees: 0)
        #expect(abs(upright.y - -1) < 0.001)
        #expect(!LevelMaths.isSurfaceMode(gravity: upright))

        // Raising the top edge by 5° reads -5° on the Y axis, which is what sends the
        // bubble up the screen towards the raised edge, as a real spirit level does.
        let tilted = LevelMaths.gravity(pitchDegrees: 5, rollDegrees: 0)
        #expect(abs(LevelMaths.surfaceAngles(gravity: tilted).y + 5) < 0.01)
    }
}
