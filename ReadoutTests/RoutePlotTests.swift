import CoreGraphics
import Foundation
import Testing
@testable import Readout

/// Reading a recorded route back out of a session's CSV and drawing it without a map server
/// (R-76, R-59).
@Suite("Recorded routes")
struct RoutePlotTests {
    /// A short walk north-east, one fix a second.
    private func walk(count: Int = 5) -> [RecordedCoordinate] {
        (0..<count).map { index in
            RecordedCoordinate(
                index: index,
                elapsed: Double(index),
                latitude: 1.3521 + Double(index) * 0.001,
                longitude: 103.8198 + Double(index) * 0.001
            )
        }
    }

    // MARK: - Reading the route back

    @Test("Latitude and longitude are paired in the order they were logged")
    func pairsTheTwoChannels() {
        let series = RecordedSeries(
            elapsed: [0, 1, 2],
            channels: [[1.0, 2.0, 3.0], [10.0, 20.0, 30.0]]
        )
        let route = series.coordinates()
        #expect(route.map(\.latitude) == [1, 2, 3])
        #expect(route.map(\.longitude) == [10, 20, 30])
        #expect(route.map(\.elapsed) == [0, 1, 2])
    }

    /// Core Location writes a fix it never got as an empty cell, which reads back as NaN.
    /// Drawing one puts a break in the line that CoreGraphics rejects outright.
    @Test("A fix that is not a position is left out rather than drawn")
    func dropsFixesThatAreNotPositions() {
        let series = RecordedSeries(
            elapsed: [0, 1, 2, 3],
            channels: [
                [1.0, .nan, 91.0, 3.0],
                [10.0, 20.0, 30.0, 200.0],
            ]
        )
        // Row 1 has no latitude, row 2 is off the globe in latitude, row 3 in longitude.
        #expect(series.coordinates().map(\.latitude) == [1])
    }

    @Test("A session with no coordinates track has no route")
    func noRouteWithoutChannels() {
        #expect(RecordedSeries.empty.coordinates().isEmpty)
        #expect(RecordedSeries(elapsed: [0], channels: [[1.0]]).coordinates().isEmpty)
    }

    @Test("A long route is thinned, keeping its first fix and its shape")
    func thinsALongRoute() {
        let count = 5_000
        let series = RecordedSeries(
            elapsed: (0..<count).map(Double.init),
            channels: [
                (0..<count).map { 1 + Double($0) * 0.0001 },
                (0..<count).map { 103 + Double($0) * 0.0001 },
            ]
        )
        let route = series.coordinates(limit: 500)
        #expect(route.count <= 501)
        #expect(route.count > 400)
        #expect(route.first?.elapsed == 0)
        // Each kept fix still carries the latitude and longitude of the same row.
        for fix in route {
            #expect(abs(fix.latitude - (1 + fix.elapsed * 0.0001)) < 1e-9)
            #expect(abs(fix.longitude - (103 + fix.elapsed * 0.0001)) < 1e-9)
        }
    }

    @Test("Every fix is given an identity of its own, even where two share an elapsed time")
    func fixesAreDistinct() {
        let series = RecordedSeries(elapsed: [1, 1, 1], channels: [[1, 2, 3], [4, 5, 6]])
        #expect(Set(series.coordinates().map(\.id)).count == 3)
    }

    // MARK: - Drawing it

    @Test("An empty route has nothing to lay out")
    func emptyRouteHasNoLayout() {
        #expect(RoutePlot.layout([], in: CGSize(width: 100, height: 100)) == nil)
        #expect(RoutePlot.layout(walk(), in: .zero) == nil)
    }

    @Test("Every fix lands inside the box it was given")
    func layoutStaysInsideTheBox() throws {
        let size = CGSize(width: 300, height: 200)
        let layout = try #require(RoutePlot.layout(walk(count: 40), in: size))
        #expect(layout.points.count == 40)
        for point in layout.points {
            #expect(point.x >= 0 && point.x <= size.width)
            #expect(point.y >= 0 && point.y <= size.height)
        }
    }

    /// North is up: a route walked northwards must come out with decreasing y.
    @Test("North is up and east is right")
    func orientation() throws {
        let northward = [
            RecordedCoordinate(index: 0, elapsed: 0, latitude: 1.0, longitude: 103.0),
            RecordedCoordinate(index: 1, elapsed: 1, latitude: 1.1, longitude: 103.1),
        ]
        let layout = try #require(RoutePlot.layout(northward, in: CGSize(width: 200, height: 200)))
        #expect(layout.points[1].y < layout.points[0].y)
        #expect(layout.points[1].x > layout.points[0].x)
    }

    /// One scale for both axes, or a journey that ran mostly north would be stretched sideways
    /// to fill the box and stop looking like itself.
    @Test("The route's shape is kept rather than stretched to fill the box")
    func aspectRatioIsKept() throws {
        // Ten times as far north as east, at the equator where a degree is a degree.
        let route = [
            RecordedCoordinate(index: 0, elapsed: 0, latitude: 0, longitude: 0),
            RecordedCoordinate(index: 1, elapsed: 1, latitude: 0.1, longitude: 0.01),
        ]
        let layout = try #require(RoutePlot.layout(route, in: CGSize(width: 200, height: 200)))
        let width = abs(layout.points[1].x - layout.points[0].x)
        let height = abs(layout.points[1].y - layout.points[0].y)
        #expect(height > width * 9)
        #expect(height < width * 11)
    }

    /// A recording made sitting at a desk has a bounding box of no width at all, which is a
    /// division by zero waiting to happen.
    @Test("A route that never moved still lays out, in the middle")
    func stationaryRoute() throws {
        let still = (0..<5).map {
            RecordedCoordinate(index: $0, elapsed: Double($0), latitude: 1.35, longitude: 103.8)
        }
        let size = CGSize(width: 200, height: 160)
        let layout = try #require(RoutePlot.layout(still, in: size))
        #expect(layout.points.count == 5)
        for point in layout.points {
            #expect(abs(point.x - size.width / 2) < 1)
            #expect(abs(point.y - size.height / 2) < 1)
            #expect(point.x.isFinite && point.y.isFinite)
        }
    }

    // MARK: - Distance and the scale bar

    @Test("Distance is summed along the route")
    func distanceAlongTheRoute() {
        #expect(RoutePlot.distance([]) == 0)
        #expect(RoutePlot.distance([walk()[0]]) == 0)

        // A tenth of a degree of latitude is about 11.1 km.
        let northward = [
            RecordedCoordinate(index: 0, elapsed: 0, latitude: 0, longitude: 0),
            RecordedCoordinate(index: 1, elapsed: 1, latitude: 0.1, longitude: 0),
        ]
        let metres = RoutePlot.distance(northward)
        #expect(metres > 11_000 && metres < 11_200)
    }

    @Test("The scale bar is a number somebody would say out loud")
    func scaleBarIsRound() throws {
        let bar = try #require(RoutePlot.scaleBar(metresPerPoint: 1, maximumWidth: 120))
        #expect(bar.metres == 100)
        #expect(abs(bar.width - 100) < 0.001)

        // 100 points of a 0.1 m-per-point plot is ten metres exactly.
        let fine = try #require(RoutePlot.scaleBar(metresPerPoint: 0.1, maximumWidth: 100))
        #expect(fine.metres == 10)
        let coarse = try #require(RoutePlot.scaleBar(metresPerPoint: 100, maximumWidth: 100))
        #expect(coarse.metres == 10_000)
    }

    @Test("A bar that would not fit is not drawn at all")
    func scaleBarCanBeImpossible() {
        // A metre per point with a bar only half a point wide: even 0.1 m will not fit.
        #expect(RoutePlot.scaleBar(metresPerPoint: 1, maximumWidth: 0.01) == nil)
        #expect(RoutePlot.scaleBar(metresPerPoint: 0, maximumWidth: 100) == nil)
        #expect(RoutePlot.scaleBar(metresPerPoint: .nan, maximumWidth: 100) == nil)
    }
}
