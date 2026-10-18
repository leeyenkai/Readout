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
        switch format {
        case .decimal:
            let lat = decimal(abs(latitude), digits: 5)
            let lon = decimal(abs(longitude), digits: 5)
            return "\(lat)° \(latitude < 0 ? "S" : "N")  \(lon)° \(longitude < 0 ? "W" : "E")"
        case .degreesMinutesSeconds:
            return "\(sexagesimal(latitude, positive: "N", negative: "S"))  \(sexagesimal(longitude, positive: "E", negative: "W"))"
        }
    }

    static func sexagesimal(_ value: Double, positive: String, negative: String) -> String {
        let magnitude = abs(value)
        let degrees = Int(magnitude)
        let minutesValue = (magnitude - Double(degrees)) * 60
        let minutes = Int(minutesValue)
        let seconds = (minutesValue - Double(minutes)) * 60
        return "\(degrees)° \(minutes)′ \(decimal(seconds, digits: 1))″ \(value < 0 ? negative : positive)"
    }

    /// The compass point a heading falls in, for example 247° → "WSW".
    static func cardinal(_ degrees: Double) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        let normalised = degrees.truncatingRemainder(dividingBy: 360)
        let positive = normalised < 0 ? normalised + 360 : normalised
        let index = Int((positive / 22.5).rounded()) % points.count
        return points[index]
    }
}
