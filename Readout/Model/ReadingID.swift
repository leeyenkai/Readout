import CoreTransferable
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

/// Lets a tile be dragged into a new position on the grid (R-22).
///
/// Carried as plain text holding the raw value: a drop of anything else simply fails to
/// decode and is ignored, which is all the validation a reorder needs.
extension ReadingID: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .plainText)
    }
}
