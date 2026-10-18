import SwiftUI

/// Axis colours are fixed across the whole app: x red, y green, z blue (R-49).
enum Axis: String, CaseIterable, Identifiable, Sendable {
    case x, y, z

    var id: String { rawValue }

    var label: String { rawValue.uppercased() }

    var colour: Color {
        switch self {
        case .x: .red
        case .y: .green
        case .z: .blue
        }
    }
}
