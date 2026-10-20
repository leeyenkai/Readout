import SwiftUI

/// How large Readout draws itself, over and above the text size set in iOS Settings (R-78).
///
/// This is a step along the system's own type scale, not a magnification of the finished
/// screen. Scaling a rendered view would blur the text and leave every tap target where it
/// was; moving along the type scale is what makes a Form row, a navigation title, a tab bar
/// label and a 64-point readout all grow together, each laid out properly at the new size.
///
/// It composes with Dynamic Type rather than replacing it: somebody who has already asked
/// iOS for large text gets large text plus whatever they choose here, and the accessibility
/// sizes are reached only by somebody already in them.
enum InterfaceScale: Int, CaseIterable, Identifiable, Codable, Sendable {
    case smaller = -2
    case small = -1
    case standard = 0
    case large = 1
    case larger = 2
    case largest = 3

    var id: Int { rawValue }

    static let `default` = InterfaceScale.standard

    var title: String {
        switch self {
        case .smaller: "Smaller"
        case .small: "Small"
        case .standard: "Default"
        case .large: "Large"
        case .larger: "Larger"
        case .largest: "Largest"
        }
    }

    /// How this sits against the phone's own setting, so it is clear the two combine rather
    /// than one overruling the other.
    var detail: String {
        switch rawValue {
        case 0:
            "Matches the text size set in iOS Settings."
        case let steps where steps < 0:
            "\(-steps) \(Self.stepWord(-steps)) smaller than the text size set in iOS Settings."
        case let steps:
            "\(steps) \(Self.stepWord(steps)) larger than the text size set in iOS Settings."
        }
    }

    /// The size to draw at, given the one the phone is set to.
    ///
    /// Clamped at both ends of the type scale. From the default size the control spans
    /// `.small` to `.xxxLarge` and stops short of the accessibility sizes, so a tap on
    /// "Largest" cannot land somebody in a size they would then struggle to read their way
    /// back out of (R-52).
    func applied(to size: DynamicTypeSize) -> DynamicTypeSize {
        let sizes = DynamicTypeSize.allCases
        guard let current = sizes.firstIndex(of: size) else { return size }
        return sizes[(current + rawValue).clamped(to: 0...(sizes.count - 1))]
    }

    private static func stepWord(_ count: Int) -> String {
        count == 1 ? "step" : "steps"
    }
}
