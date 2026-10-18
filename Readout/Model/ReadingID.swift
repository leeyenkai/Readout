import Foundation

/// Every reading Readout can show. Raw values are persisted in the tile layout,
/// so they must not change once shipped.
enum ReadingID: String, CaseIterable, Identifiable, Codable, Sendable {
    // Motion
    case acceleration
    case rotationRate
    case orientation
    case magneticField
    case heading

    // Environment
    case airPressure
    case relativeAltitude
    case soundLevel
    case light

    // Location
    case coordinates
    case gpsAltitude
    case speed
    case course
    case locationAccuracy

    // Device & activity
    case activity
    case cadence
    case proximity
    case battery
    case thermalState

    var id: String { rawValue }
}
