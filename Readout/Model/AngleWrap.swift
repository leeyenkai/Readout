import Foundation

/// How a channel's angle wraps round the circle: heading and course run 0…360, yaw and roll
/// run −180…180.
///
/// An angle is not an ordinary number. A compass jittering between 358° and 2° is pointing
/// north, but the plain average of those two figures is 180° — due south — and the plain
/// minimum and maximum say it swung through the whole dial. Channels that wrap say so, and
/// their statistics are worked out round the circle instead (P-2).
enum AngleWrap: Sendable, Hashable {
    /// 0 ..< 360: heading, course.
    case fullTurn
    /// −180 ..< 180: Core Motion's yaw and roll.
    case halfTurn

    /// The lowest value of the range, which is also where an angle that has covered the whole
    /// circle is said to start.
    var lowerBound: Double {
        switch self {
        case .fullTurn: 0
        case .halfTurn: -180
        }
    }

    var upperBound: Double { lowerBound + 360 }

    /// Folds any angle into this range.
    func normalised(_ degrees: Double) -> Double {
        guard degrees.isFinite else { return degrees }
        let shifted = (degrees - lowerBound).truncatingRemainder(dividingBy: 360)
        return (shifted < 0 ? shifted + 360 : shifted) + lowerBound
    }
}
