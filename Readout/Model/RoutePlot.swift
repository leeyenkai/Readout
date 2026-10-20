import CoreGraphics
import Foundation

/// Drawing a recorded route without a map server (R-76, R-59).
///
/// Readout makes no network requests, and a street map is somebody else's tiles fetched over
/// one. So the route is plotted from the session's own CSV instead: a local equirectangular
/// projection, where longitude is scaled by the cosine of the route's middle latitude so that
/// a square on screen is a square on the ground. Over a journey of a few hundred kilometres
/// the error in that is far narrower than the line drawn on top of it, and the whole thing
/// works on a plane with the radio off.
///
/// Pure arithmetic, so the projection and the scale bar are covered by tests without a map,
/// a camera or a fix (AGENTS §5).
enum RoutePlot {
    /// Metres per degree of latitude. Good to a few parts in a thousand anywhere on Earth,
    /// which is far better than a GPS fix.
    static let metresPerDegree: Double = 111_320

    /// Where a route's fixes land inside a box, and how much ground a point on screen covers.
    struct Layout: Equatable {
        let points: [CGPoint]
        /// Metres of ground per point of screen, for the scale bar.
        let metresPerPoint: Double
    }

    /// Projects a route into `size`, leaving `inset` points clear at every edge.
    ///
    /// Returns nothing for an empty route. A route that never moved — a recording made
    /// sitting still — is given an arbitrary small span so that its single dot lands in the
    /// middle of the box rather than dividing by a zero-width bounding box.
    static func layout(_ route: [RecordedCoordinate], in size: CGSize, inset: Double = 14) -> Layout? {
        guard !route.isEmpty, size.width > 0, size.height > 0 else { return nil }

        let latitudes = route.map(\.latitude)
        let centreLatitude = ((latitudes.min() ?? 0) + (latitudes.max() ?? 0)) / 2
        // Towards the poles a degree of longitude is a short distance on the ground; at the
        // pole itself it is none at all, which the floor keeps out of the division below.
        let convergence = max(cos(centreLatitude * .pi / 180), 0.01)

        let projected = route.map { fix in
            CGPoint(x: fix.longitude * convergence, y: -fix.latitude)
        }
        let xs = projected.map(\.x)
        let ys = projected.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return nil }

        let usableWidth = max(size.width - 2 * inset, 1)
        let usableHeight = max(size.height - 2 * inset, 1)
        // A stationary recording has no span at all. About a metre, so the dot is a dot.
        let fallbackSpan = 1 / metresPerDegree
        let spanX = max(maxX - minX, fallbackSpan)
        let spanY = max(maxY - minY, fallbackSpan)
        // One scale for both axes, or the route's shape would be stretched to fill the box.
        let scale = min(usableWidth / spanX, usableHeight / spanY)

        // Placed around the middle of the box rather than from a corner of the bounding box.
        // The two agree for any route that actually went somewhere, but a recording made
        // sitting still has no bounding box to speak of — and measuring from its corner put
        // the single dot in the corner of the plot instead of the centre.
        let centreX = (minX + maxX) / 2
        let centreY = (minY + maxY) / 2
        let placed = projected.map { point in
            CGPoint(
                x: size.width / 2 + (point.x - centreX) * scale,
                y: size.height / 2 + (point.y - centreY) * scale
            )
        }
        return Layout(points: placed, metresPerPoint: metresPerDegree / scale)
    }

    /// How far the route runs along the ground, in metres.
    ///
    /// Summed fix to fix with the haversine formula, which is right over a short hop where
    /// the flat projection above would start to show — the plot is for looking at, this is a
    /// number shown to the user.
    static func distance(_ route: [RecordedCoordinate]) -> Double {
        guard route.count > 1 else { return 0 }
        var total: Double = 0
        for (previous, next) in zip(route, route.dropFirst()) {
            total += separation(previous, next)
        }
        return total
    }

    /// Great-circle distance between two fixes, in metres.
    static func separation(_ a: RecordedCoordinate, _ b: RecordedCoordinate) -> Double {
        let radius: Double = 6_371_000
        let φ1 = a.latitude * .pi / 180
        let φ2 = b.latitude * .pi / 180
        let Δφ = φ2 - φ1
        let Δλ = (b.longitude - a.longitude) * .pi / 180
        let h = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * radius * asin(min(1, sqrt(max(h, 0))))
    }

    /// A round distance for the scale bar and how wide it is on screen, or nothing when even
    /// the smallest round step would not fit.
    ///
    /// Round in the sense a map is round: 10, 20 or 50 metres and the same again every
    /// decade, so the bar always reads as a number somebody would say out loud.
    static func scaleBar(metresPerPoint: Double, maximumWidth: Double) -> (metres: Double, width: Double)? {
        guard metresPerPoint > 0, metresPerPoint.isFinite, maximumWidth > 0 else { return nil }
        let widest = metresPerPoint * maximumWidth
        var best: Double?
        for decade in -1...7 {
            for step in [1.0, 2.0, 5.0] {
                let candidate = step * pow(10, Double(decade))
                if candidate <= widest { best = candidate }
            }
        }
        guard let metres = best else { return nil }
        return (metres, metres / metresPerPoint)
    }
}
