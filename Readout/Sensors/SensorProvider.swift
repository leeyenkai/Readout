import Foundation

/// How often a reading needs to arrive. Tiles are happy at 10 Hz; the level, the compass and
/// the detail chart want display rate (R-65).
enum ActivationRate: Int, Comparable, Sendable {
    case standard = 10
    case display = 60

    static func < (lhs: ActivationRate, rhs: ActivationRate) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var interval: TimeInterval { 1 / Double(rawValue) }
}

/// What the UI should do with a reading right now.
enum ReadingAvailability: Sendable, Equatable {
    /// Running and delivering values.
    case live
    /// Supported and permitted, but not started — the "Tap to measure" tiles (R-19).
    case ready
    /// Needs a permission that has not been asked for yet (R-20).
    case needsPermission(SensorPermission)
    /// The permission was refused; the tile offers a route to Settings (R-55).
    case denied(SensorPermission)
    /// This device has no such sensor, so the tile is hidden entirely (R-7, R-21).
    case unavailable

    var isUsable: Bool {
        switch self {
        case .live, .ready: true
        case .needsPermission, .denied, .unavailable: false
        }
    }
}

/// One source of readings, wrapping exactly one Apple framework.
///
/// Providers are owned by `SensorHub` and never created by a view (R-63).
@MainActor
protocol SensorProvider: AnyObject {
    /// The readings this provider can deliver.
    var readings: Set<ReadingID> { get }

    /// Set by the hub; providers call it whenever a new value arrives.
    var output: ((ReadingID, SensorSample) -> Void)? { get set }

    /// Whether this device has the hardware. Checked at runtime, never assumed.
    func isSupported(_ reading: ReadingID) -> Bool

    func start(_ reading: ReadingID, rate: ActivationRate)
    func stop(_ reading: ReadingID)
}

extension SensorProvider {
    func stopAll() {
        for reading in readings { stop(reading) }
    }
}
