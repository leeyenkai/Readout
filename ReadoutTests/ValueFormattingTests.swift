import Foundation
import Testing
@testable import Readout

@Suite("Units and formatting")
struct ValueFormattingTests {
    @Test("Pressure converts from hectopascal to inches of mercury")
    func pressureConversion() {
        let metric = ValueFormatting.format(1_013.26, unit: .pressure, units: DisplayUnits(system: .metric))
        #expect(metric.symbol == "hPa")
        #expect(metric.text == "1,013.3")

        let imperial = ValueFormatting.format(1_013.25, unit: .pressure, units: DisplayUnits(system: .imperial))
        #expect(imperial.symbol == "inHg")
        #expect(Double(imperial.text) == 29.92)
    }

    @Test("Altitude converts from metres to feet")
    func altitudeConversion() {
        let imperial = ValueFormatting.format(100, unit: .altitude, units: DisplayUnits(system: .imperial))
        #expect(imperial.symbol == "ft")
        #expect(imperial.text == "328.1")
    }

    @Test("Speed converts from metres per second")
    func speedConversion() {
        let metric = ValueFormatting.format(10, unit: .speed, units: DisplayUnits(system: .metric))
        #expect(metric.text == "36.0")
        #expect(metric.symbol == "km/h")

        let imperial = ValueFormatting.format(10, unit: .speed, units: DisplayUnits(system: .imperial))
        #expect(imperial.text == "22.4")
        #expect(imperial.symbol == "mph")
    }

    @Test("Acceleration follows its own preference rather than the region")
    func accelerationUnits() {
        let g = ValueFormatting.format(1, unit: .acceleration, units: DisplayUnits(acceleration: .gravity))
        #expect(g.spoken == "1.00 g")

        let si = ValueFormatting.format(1, unit: .acceleration, units: DisplayUnits(acceleration: .metricSI))
        #expect(si.spoken == "9.8 m/s²")
    }

    @Test("Pace is written as minutes and seconds")
    func paceFormatting() {
        let metric = ValueFormatting.format(330, unit: .pace, units: DisplayUnits(system: .metric))
        #expect(metric.text == "5:30")
        #expect(metric.symbol == "/km")

        // A mile takes longer than a kilometre at the same pace.
        let imperial = ValueFormatting.format(330, unit: .pace, units: DisplayUnits(system: .imperial))
        #expect(imperial.text == "8:51")
    }

    @Test("Non-finite values never reach the screen as numbers")
    func nonFiniteValues() {
        #expect(ValueFormatting.decimal(.nan, digits: 1) == "—")
        #expect(ValueFormatting.decimal(.infinity, digits: 1) == "—")
        #expect(ValueFormatting.duration(0) == "—")
        #expect(ValueFormatting.duration(-5) == "—")
    }

    @Test("Coordinates read as decimal degrees or as degrees, minutes and seconds")
    func coordinateFormatting() {
        let decimal = ValueFormatting.coordinate(latitude: 1.3521, longitude: -103.8198, format: .decimal)
        #expect(decimal.contains("1.35210° N"))
        #expect(decimal.contains("103.81980° W"))

        let sexagesimal = ValueFormatting.coordinate(latitude: -1.5, longitude: 103.5, format: .degreesMinutesSeconds)
        #expect(sexagesimal.contains("1° 30′ 0.0″ S"))
        #expect(sexagesimal.contains("103° 30′ 0.0″ E"))
    }

    @Test("Headings map to compass points", arguments: [
        (0.0, "N"), (90.0, "E"), (180.0, "S"), (270.0, "W"), (247.0, "WSW"), (359.0, "N"),
    ])
    func cardinalPoints(degrees: Double, expected: String) {
        #expect(ValueFormatting.cardinal(degrees) == expected)
    }

    /// Core Location reports an unknown position as `kCLLocationCoordinate2DInvalid`, whose
    /// components are NaN, and `Int(_: Double)` traps on NaN rather than clamping. Both of
    /// these used to crash the app outright.
    @Test("A position the phone does not have formats as a dash instead of crashing", arguments: [
        Double.nan, .infinity, -.infinity,
    ])
    func nonFiniteCoordinates(value: Double) {
        #expect(ValueFormatting.sexagesimal(value, positive: "N", negative: "S") == "—")
        #expect(ValueFormatting.cardinal(value) == "—")
        #expect(ValueFormatting.coordinate(latitude: value, longitude: value, format: .degreesMinutesSeconds).contains("—"))
        #expect(ValueFormatting.coordinate(latitude: value, longitude: value, format: .decimal).contains("—"))
    }

    @Test("A chart's time axis reads as a distance back from now")
    func relativeTime() {
        #expect(ValueFormatting.relativeTime(secondsAgo: 0) == "now")
        #expect(ValueFormatting.relativeTime(secondsAgo: 0.4) == "now")
        #expect(ValueFormatting.relativeTime(secondsAgo: 5) == "−5 s")
        #expect(ValueFormatting.relativeTime(secondsAgo: 59) == "−59 s")
        #expect(ValueFormatting.relativeTime(secondsAgo: 60) == "−1 min")
        #expect(ValueFormatting.relativeTime(secondsAgo: 150) == "−3 min")
        #expect(ValueFormatting.relativeTime(secondsAgo: .nan).isEmpty)
    }

    /// 1° 59′ 59.96″ rounds to a whole two degrees, not to "59′ 60.0″".
    @Test("Seconds that round up carry into the minutes and degrees")
    func sexagesimalCarries() {
        let almostTwo = 2 - 0.04 / 3_600
        #expect(ValueFormatting.sexagesimal(almostTwo, positive: "N", negative: "S") == "2° 0′ 0.0″ N")
        let almostHalf = 0.5 - 0.03 / 3_600
        #expect(ValueFormatting.sexagesimal(almostHalf, positive: "E", negative: "W") == "0° 30′ 0.0″ E")
    }

    @Test("A value that rounds to zero is not shown with a minus sign")
    func noNegativeZero() {
        #expect(ValueFormatting.decimal(-0.001, digits: 2) == "0.00")
        #expect(ValueFormatting.decimal(-0.4, digits: 0) == "0")
        #expect(ValueFormatting.decimal(-0.006, digits: 2) == "-0.01")
    }
}

