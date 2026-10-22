import Foundation

/// The angle arithmetic behind the compass, kept out of the view so it is covered by tests
/// without a magnetometer (R-33, R-51).
enum CompassMaths {
    /// How close to a cardinal point counts as being on it, in degrees.
    static let cardinalTolerance: Double = 2

    /// Which cardinal point a heading is sitting on — 0 north, 1 east, 2 south, 3 west — or
    /// nothing when it is between two of them.
    ///
    /// The dial's haptic follows this rather than the *nearest* cardinal point. Nearest
    /// changes as the heading crosses 45°, 135°, 225° and 315°, so the tap meant to mark
    /// north was felt exactly halfway between north and east (R-51).
    static func cardinalCrossing(heading: Double, tolerance: Double = cardinalTolerance) -> Int? {
        guard heading.isFinite else { return nil }
        let positive = normalised(heading)
        let nearest = (positive / 90).rounded()
        guard abs(positive - nearest * 90) <= tolerance else { return nil }
        // 360° rounds to the fourth quarter turn, which is north again.
        return Int(nearest.truncatingRemainder(dividingBy: 4))
    }

    /// How far a heading has drifted from a locked bearing, as a signed angle: negative to
    /// the left of it, positive to the right, never more than half a turn either way (R-33).
    static func drift(from bearing: Double, to heading: Double) -> Double {
        guard bearing.isFinite, heading.isFinite else { return 0 }
        return (heading - bearing + 540).truncatingRemainder(dividingBy: 360) - 180
    }

    /// The next heading, kept continuous with the one before: 350° followed by 10° is 370°.
    ///
    /// The dial turns to the heading with an animation, and animating from 359° to 1° turns
    /// the long way round — a full spin through south to move two degrees. Keeping the turns
    /// means the dial only ever takes the short way.
    static func unwrapped(previous: Double, next: Double) -> Double {
        guard previous.isFinite else { return normalised(next) }
        guard next.isFinite else { return previous }
        return previous + drift(from: normalised(previous), to: normalised(next))
    }

    /// A heading folded into 0..<360, so a provider reporting 361° or −1° still lands where
    /// it belongs on the dial.
    static func normalised(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }
}
