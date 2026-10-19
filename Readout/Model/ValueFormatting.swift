import Foundation

/// Every number shown to the user goes through here, so units and digits stay consistent.
struct ValueFormatting {
    /// A number and its unit, kept apart so the unit can be set in smaller type.
    struct Formatted: Sendable, Equatable {
        var text: String
        var symbol: String
        /// Number and unit together, for copying and VoiceOver.
        var spoken: String { symbol.isEmpty ? text : "\(text) \(symbol)" }
    }

    static func format(_ storedValue: Double, unit: ValueUnit, units: DisplayUnits) -> Formatted {
        let presentation = unit.presentation(units)
        let converted = presentation.convert(storedValue)
        switch presentation.style {
        case .decimal:
            return Formatted(text: decimal(converted, digits: presentation.digits), symbol: presentation.symbol)
        case .duration:
            return Formatted(text: duration(converted), symbol: presentation.symbol)
        }
    }

    /// Fixed-digit decimal with grouping, so live values keep a stable width (R-47).
    static func decimal(_ value: Double, digits: Int) -> String {
        guard value.isFinite else { return "—" }
        return value.formatted(
            .number
                .precision(.fractionLength(digits))
                .grouping(.automatic)
        )
    }

    /// Seconds as m:ss, for pace. Zero or non-finite becomes an em dash.
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0, seconds < 60 * 100 else { return "—" }
        let total = Int(seconds.rounded())
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// Latitude and longitude, decimal or sexagesimal (R-8).
    static func coordinate(latitude: Double, longitude: Double, format: CoordinateFormat) -> String {
        let pair = coordinatePair(latitude: latitude, longitude: longitude, format: format)
        return "\(pair.latitude)  \(pair.longitude)"
    }

    /// The same pair kept apart, for a place too narrow to hold both on one line — a tile is
    /// half the width of the screen, and a coordinate truncated mid-digit says nothing.
    static func coordinatePair(
        latitude: Double,
        longitude: Double,
        format: CoordinateFormat
    ) -> (latitude: String, longitude: String) {
        switch format {
        case .decimal:
            return (
                "\(decimal(abs(latitude), digits: 5))° \(latitude < 0 ? "S" : "N")",
                "\(decimal(abs(longitude), digits: 5))° \(longitude < 0 ? "W" : "E")"
            )
        case .degreesMinutesSeconds:
            return (
                sexagesimal(latitude, positive: "N", negative: "S"),
                sexagesimal(longitude, positive: "E", negative: "W")
            )
        }
    }

    static func sexagesimal(_ value: Double, positive: String, negative: String) -> String {
        // Core Location reports an unknown position as kCLLocationCoordinate2DInvalid, whose
        // components are NaN. Int(_: Double) traps on NaN rather than clamping, so the guard
        // has to come before the conversion below.
        guard value.isFinite else { return "—" }
        let magnitude = abs(value)
        let degrees = Int(magnitude)
        let minutesValue = (magnitude - Double(degrees)) * 60
        let minutes = Int(minutesValue)
        let seconds = (minutesValue - Double(minutes)) * 60
        return "\(degrees)° \(minutes)′ \(decimal(seconds, digits: 1))″ \(value < 0 ? negative : positive)"
    }

    /// A point on a live chart's time axis, as the distance back from now: "now", "−5 s",
    /// "−2 min". A wall-clock time means nothing on a ten-second chart (R-25).
    static func relativeTime(secondsAgo: Double) -> String {
        guard secondsAgo.isFinite else { return "" }
        let rounded = secondsAgo.rounded()
        guard rounded >= 1 else { return "now" }
        guard rounded >= 60 else { return "−\(Int(rounded)) s" }
        let minutes = (rounded / 60).rounded()
        return "−\(Int(minutes)) min"
    }

    /// The compass point a heading falls in, for example 247° → "WSW".
    static func cardinal(_ degrees: Double) -> String {
        guard degrees.isFinite else { return "—" }
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalised < 0 ? normalised + 360 : normalised
        let index = Int((positive / 22.5).rounded()) % points.count
        return points[index]
    }
}
