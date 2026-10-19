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

    /// A dash pattern per axis, so the three series are still told apart with Differentiate
    /// Without Colour on, or by anyone who cannot separate red from green (R-49, R-52).
    var dash: [CGFloat] {
        switch self {
        case .x: []
        case .y: [6, 3]
        case .z: [2, 3]
        }
    }
}
