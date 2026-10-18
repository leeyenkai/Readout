import Foundation

/// How often a recording keeps a sample (R-39).
///
/// The rate is a ceiling, not a promise: only the four Core Motion readings can be driven
/// faster than their default, so location, air pressure and the pedometer arrive at their own
/// rate whatever is chosen here (`RecordingCadence.native`).
enum RecordingRate: String, CaseIterable, Identifiable, Codable, Sendable {
    case low
    case medium
    case high

    var id: String { rawValue }

    var hertz: Double {
        switch self {
        case .low: 1
        case .medium: 10
        case .high: 50
        }
    }

    var interval: TimeInterval { 1 / hertz }

    var title: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }

    /// Shown next to the picker, so the number is never a mystery.
    var detail: String {
        switch self {
        case .low: "1 Hz — one sample a second"
        case .medium: "10 Hz — ten samples a second"
        case .high: "50 Hz — motion readings only"
        }
    }

    /// The rate the hub is asked for. 1 Hz and 10 Hz are both comfortably inside the
    /// standard 10 Hz activation; High asks Core Motion for 50 Hz (R-39, R-65).
    var activationRate: ActivationRate {
        switch self {
        case .low, .medium: .standard
        case .high: .fast
        }
    }

    /// How a finished session names its rate.
    var summary: String { "\(title) · \(ValueFormatting.decimal(hertz, digits: 0)) Hz" }
}
