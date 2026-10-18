import Foundation

/// The four sections of the Readings grid, in display order.
enum ReadingGroup: String, CaseIterable, Identifiable, Sendable {
    case motion
    case environment
    case location
    case device

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motion: "Motion"
        case .environment: "Environment"
        case .location: "Location"
        case .device: "Device & activity"
        }
    }

    var symbol: String {
        switch self {
        case .motion: "move.3d"
        case .environment: "cloud.sun"
        case .location: "location"
        case .device: "iphone.gen3"
        }
    }
}
