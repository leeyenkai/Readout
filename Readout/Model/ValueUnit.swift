import Foundation

/// Which measurement system to show values in. `.automatic` follows the phone's region.
enum UnitSystem: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic, metric, imperial

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .metric: "Metric"
        case .imperial: "Imperial"
        }
    }

    /// Resolves `.automatic` against a locale.
    func resolved(for locale: Locale = .autoupdatingCurrent) -> ResolvedUnitSystem {
        switch self {
        case .metric: .metric
        case .imperial: .imperial
        case .automatic: locale.measurementSystem == .metric ? .metric : .imperial
        }
    }
}

enum ResolvedUnitSystem: Sendable { case metric, imperial }

/// Acceleration is a preference rather than a regional difference, so it gets its own switch.
enum AccelerationUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case gravity, metricSI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gravity: "g"
        case .metricSI: "m/s²"
        }
    }
}

/// The resolved display preferences a formatter needs.
struct DisplayUnits: Sendable, Equatable {
    var system: ResolvedUnitSystem = .metric
    var acceleration: AccelerationUnit = .gravity
    var coordinates: CoordinateFormat = .decimal

    static let metricDefault = DisplayUnits()
}

enum CoordinateFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case decimal, degreesMinutesSeconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .decimal: "Decimal"
        case .degreesMinutesSeconds: "D° M′ S″"
        }
    }
}

/// The unit a channel's values are stored in. Stored values are always the metric base unit;
/// conversion happens at display time.
enum ValueUnit: Sendable, Equatable, Hashable {
    /// Stored in g.
    case acceleration
    /// Stored in degrees per second.
    case angularVelocity
    /// Stored in degrees.
    case angle
    /// Stored in microtesla.
    case magneticFlux
    /// Stored in hectopascal.
    case pressure
    /// Stored in metres.
    case altitude
    /// Stored in metres, shown without an imperial conversion below a metre.
    case length
    /// Stored in decibel (estimated SPL).
    case soundPressure
    /// Stored in lux.
    case illuminance
    /// Stored in metres per second.
    case speed
    /// Stored in metres.
    case distance
    /// Stored in kilometres per hour equivalents is avoided; counts have no unit.
    case count(symbol: String)
    /// Stored in steps per minute.
    case cadence
    /// Stored in seconds per kilometre; displayed as m:ss.
    case pace
    /// Stored in percent.
    case percentage
    /// A discrete reading with no numeric unit.
    case none

    /// Conversion and formatting rules for the current preferences.
    func presentation(_ units: DisplayUnits) -> UnitPresentation {
        switch self {
        case .acceleration:
            switch units.acceleration {
            case .gravity: UnitPresentation(symbol: "g", digits: 2, scale: 1)
            case .metricSI: UnitPresentation(symbol: "m/s²", digits: 1, scale: 9.80665)
            }
        case .angularVelocity:
            UnitPresentation(symbol: "°/s", digits: 1, scale: 1)
        case .angle:
            UnitPresentation(symbol: "°", digits: 1, scale: 1)
        case .magneticFlux:
            UnitPresentation(symbol: "µT", digits: 1, scale: 1)
        case .pressure:
            switch units.system {
            case .metric: UnitPresentation(symbol: "hPa", digits: 1, scale: 1)
            case .imperial: UnitPresentation(symbol: "inHg", digits: 2, scale: 0.029529983)
            }
        case .altitude, .length:
            switch units.system {
            case .metric: UnitPresentation(symbol: "m", digits: 1, scale: 1)
            case .imperial: UnitPresentation(symbol: "ft", digits: 1, scale: 3.280839895)
            }
        case .soundPressure:
            UnitPresentation(symbol: "dB", digits: 0, scale: 1)
        case .illuminance:
            UnitPresentation(symbol: "lux", digits: 0, scale: 1)
        case .speed:
            switch units.system {
            case .metric: UnitPresentation(symbol: "km/h", digits: 1, scale: 3.6)
            case .imperial: UnitPresentation(symbol: "mph", digits: 1, scale: 2.236936292)
            }
        case .distance:
            switch units.system {
            case .metric: UnitPresentation(symbol: "km", digits: 2, scale: 0.001)
            case .imperial: UnitPresentation(symbol: "mi", digits: 2, scale: 0.000621371)
            }
        case .count(let symbol):
            UnitPresentation(symbol: symbol, digits: 0, scale: 1)
        case .cadence:
            UnitPresentation(symbol: "steps/min", digits: 0, scale: 1)
        case .pace:
            switch units.system {
            case .metric: UnitPresentation(symbol: "/km", digits: 0, scale: 1, style: .duration)
            case .imperial: UnitPresentation(symbol: "/mi", digits: 0, scale: 1.609344, style: .duration)
            }
        case .percentage:
            UnitPresentation(symbol: "%", digits: 0, scale: 1)
        case .none:
            UnitPresentation(symbol: "", digits: 0, scale: 1)
        }
    }
}

/// How a converted value is written out.
struct UnitPresentation: Sendable, Equatable {
    enum Style: Sendable { case decimal, duration }

    let symbol: String
    let digits: Int
    let scale: Double
    let offset: Double
    let style: Style

    init(symbol: String, digits: Int, scale: Double, offset: Double = 0, style: Style = .decimal) {
        self.symbol = symbol
        self.digits = digits
        self.scale = scale
        self.offset = offset
        self.style = style
    }

    /// Converts a stored metric value into display units.
    func convert(_ storedValue: Double) -> Double {
        storedValue * scale + offset
    }
}
