import Foundation

/// A three-component vector in the phone's own frame of reference.
struct Vector3: Sendable, Equatable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = Vector3(x: 0, y: 0, z: 0)

    var magnitude: Double { sqrt(x * x + y * y + z * z) }
}

/// The geometry behind the spirit level, kept pure so it is covered by tests (R-32).
enum LevelMaths {
    /// Whether the phone is lying flat enough to use the bubble, rather than standing on an
    /// edge. Gravity points almost entirely through the screen when the phone is flat.
    static func isSurfaceMode(gravity: Vector3) -> Bool {
        abs(gravity.z) > 0.7
    }

    /// Tilt of a flat phone along its own x and y axes, in degrees.
    static func surfaceAngles(gravity: Vector3) -> (x: Double, y: Double) {
        let down = gravity.z < 0 ? -gravity.z : gravity.z
        return (
            x: atan2(gravity.x, max(down, 0.0001)).degrees,
            y: atan2(gravity.y, max(down, 0.0001)).degrees
        )
    }

    /// How far a phone standing on an edge is from level, in degrees, measured from the
    /// nearest of its four edges. Positive when the phone has turned clockwise past it.
    ///
    /// Measured from the bottom edge alone, a phone standing on its long side — the natural
    /// way to lay it along a shelf — read ±90°.
    static func edgeAngle(gravity: Vector3) -> Double {
        let turn = rawEdgeAngle(gravity: gravity)
        // Rounded here rather than taken from `edgeQuarterTurns`, which calls −180° and 180°
        // the same edge: measured from −180°, a phone just past upside down would read −359°.
        return turn - (turn / 90).rounded() * 90
    }

    /// Which edge the phone is standing on, in quarter turns clockwise from upright: 0 on its
    /// bottom edge, 1 on its left side, 2 upside down, −1 on its right side.
    static func edgeQuarterTurns(gravity: Vector3) -> Int {
        let quarters = Int((rawEdgeAngle(gravity: gravity) / 90).rounded())
        // ±180° are the same edge; call it 2 either way.
        return quarters == -2 ? 2 : quarters
    }

    private static func rawEdgeAngle(gravity: Vector3) -> Double {
        atan2(gravity.x, -gravity.y).degrees
    }

    /// Rebuilds a gravity vector from pitch and roll, for sources that report an attitude
    /// but no gravity of their own — the Simulator's synthetic source.
    ///
    /// Worked out from the same attitude the 3D view draws, so the two never disagree about
    /// which way the phone is tipped. An earlier hand-written version had the sign of x
    /// reversed: positive roll lowers the right edge, which puts gravity on +x.
    static func gravity(pitchDegrees: Double, rollDegrees: Double) -> Vector3 {
        AttitudeMaths.gravity(AttitudeMaths.attitude(
            pitchDegrees: pitchDegrees,
            rollDegrees: rollDegrees,
            yawDegrees: 0
        ))
    }

    /// Where the bubble sits in a flat phone's circle, as a fraction of the usable radius in
    /// screen coordinates (x to the right, y down).
    ///
    /// A bubble rises to the high side. With Core Motion's gravity, raising the top edge reads
    /// a negative Y angle and raising the right edge a negative X angle, so the bubble moves
    /// against X and with Y. Passing both angles straight through — as the view used to —
    /// made the bubble rise front to back but sink side to side.
    static func bubbleOffset(x: Double, y: Double, fullScale: Double = 15) -> (x: Double, y: Double) {
        let position = bubblePosition(x: x, y: y, fullScale: fullScale)
        return (x: -position.x, y: position.y)
    }

    /// Where the bubble sits along an edge level's tube, as a fraction of its travel, positive
    /// towards the tube's right. A phone turned clockwise has its right end low, so the bubble
    /// runs left.
    static func edgeBubbleOffset(angle: Double, fullScale: Double = 15) -> Double {
        guard angle.isFinite, fullScale > 0 else { return 0 }
        return -(angle / fullScale).clamped(to: -1...1)
    }

    /// Where the bubble sits inside its circle, as a fraction of the usable radius in each
    /// direction. `fullScale` is the tilt that puts the bubble on the rim.
    ///
    /// Clamped as a vector rather than one axis at a time: clamping x and y separately let a
    /// diagonal tilt reach √2 of the limit, and the bubble slid out through the corner of
    /// its own circle (R-32).
    static func bubblePosition(x: Double, y: Double, fullScale: Double = 15) -> (x: Double, y: Double) {
        guard fullScale > 0, x.isFinite, y.isFinite else { return (0, 0) }
        let fractionX = x / fullScale
        let fractionY = y / fullScale
        let magnitude = sqrt(fractionX * fractionX + fractionY * fractionY)
        guard magnitude > 1 else { return (fractionX, fractionY) }
        return (fractionX / magnitude, fractionY / magnitude)
    }

    /// Total tilt of a flat phone from horizontal, in degrees.
    static func surfaceTilt(gravity: Vector3) -> Double {
        let clamped = min(max(abs(gravity.z) / max(gravity.magnitude, 0.0001), 0), 1)
        return acos(clamped).degrees
    }
}

/// What Zero has taken off the spirit level's readings, so a phone in a lumpy case, or a
/// surface known to be true, can read 0 (R-32).
///
/// Each mode keeps its own: a correction found with the phone flat means nothing to it
/// standing on an edge, and each edge rests on different corners of the case. A single shared
/// zero meant zeroing on an edge shifted the flat reading by the same amount.
struct LevelZero: Codable, Equatable, Sendable {
    var surfaceX: Double = 0
    var surfaceY: Double = 0
    /// One per edge, indexed by `edgeIndex(quarterTurns:)`.
    var edges: [Double] = [0, 0, 0, 0]

    static let none = LevelZero()

    var isSurfaceZeroed: Bool { surfaceX != 0 || surfaceY != 0 }

    func isEdgeZeroed(quarterTurns: Int) -> Bool {
        edge(quarterTurns: quarterTurns) != 0
    }

    func surfaceAngles(gravity: Vector3) -> (x: Double, y: Double) {
        let raw = LevelMaths.surfaceAngles(gravity: gravity)
        return (x: raw.x - surfaceX, y: raw.y - surfaceY)
    }

    func edgeAngle(gravity: Vector3) -> Double {
        LevelMaths.edgeAngle(gravity: gravity) - edge(quarterTurns: LevelMaths.edgeQuarterTurns(gravity: gravity))
    }

    /// Takes the reading this gravity gives as the new zero, for whichever mode it puts the
    /// phone in. The gravity passed is the one on screen — a held reading if Hold is on —
    /// so what was zeroed is what the user was looking at.
    mutating func zero(at gravity: Vector3) {
        if LevelMaths.isSurfaceMode(gravity: gravity) {
            let raw = LevelMaths.surfaceAngles(gravity: gravity)
            surfaceX = raw.x
            surfaceY = raw.y
        } else {
            let quarter = LevelMaths.edgeQuarterTurns(gravity: gravity)
            edges = normalisedEdges
            edges[Self.edgeIndex(quarterTurns: quarter)] = LevelMaths.edgeAngle(gravity: gravity)
        }
    }

    /// Clears the zero for whichever mode this gravity puts the phone in.
    mutating func clear(at gravity: Vector3) {
        if LevelMaths.isSurfaceMode(gravity: gravity) {
            surfaceX = 0
            surfaceY = 0
        } else {
            edges = normalisedEdges
            edges[Self.edgeIndex(quarterTurns: LevelMaths.edgeQuarterTurns(gravity: gravity))] = 0
        }
    }

    private func edge(quarterTurns: Int) -> Double {
        let index = Self.edgeIndex(quarterTurns: quarterTurns)
        return edges.indices.contains(index) ? edges[index] : 0
    }

    /// Four entries whatever was decoded, so an index is always valid.
    private var normalisedEdges: [Double] {
        Array((edges + [0, 0, 0, 0]).prefix(4))
    }

    static func edgeIndex(quarterTurns: Int) -> Int {
        ((quarterTurns % 4) + 4) % 4
    }
}
