import Foundation

/// How far a recording may run before it stops itself and saves what it has (Q-4, R-80).
///
/// v0.3.0 settled on a fixed two hours and 100 MB, and that stays the default: a session
/// that quietly fills the device is worse than one that ends. But logging a journey is the
/// obvious thing to want a recording for, and plenty of journeys are longer than two hours,
/// so the ceiling is the user's to raise.
///
/// Every option keeps a storage ceiling of some kind. The open-ended one has no clock at all
/// and stops when the volume is down to the reserve: Readout will not be the reason a phone
/// has no room left for a photo.
enum RecordingLimit: String, CaseIterable, Identifiable, Codable, Sendable {
    case twoHours
    case sixHours
    case twelveHours
    case untilStorageRunsOut

    var id: String { rawValue }

    static let `default` = RecordingLimit.twoHours

    /// Decimal megabytes, because that is what `byteCount(style: .file)` writes them back
    /// as: a ceiling of 100 × 1024² reads to the user as "104.9 MB", which is nobody's idea
    /// of a round number.
    private static let megabyte = 1_000_000
    /// Left free on the volume whatever happens.
    static let reserveBytes = 500 * megabyte
    /// Room a recording needs to be worth starting at all.
    private static let workingBytes = 50 * megabyte

    var title: String {
        switch self {
        case .twoHours: "2 hours"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .untilStorageRunsOut: "Until storage runs out"
        }
    }

    /// Nil where there is no time limit at all.
    var duration: TimeInterval? {
        switch self {
        case .twoHours: 2 * 60 * 60
        case .sixHours: 6 * 60 * 60
        case .twelveHours: 12 * 60 * 60
        case .untilStorageRunsOut: nil
        }
    }

    /// The most a session may write in all, given what it has written so far and what the
    /// volume will spare.
    ///
    /// `availableBytes` is the free space *now*, which already excludes everything this
    /// session has written. The open-ended limit's room is therefore what is free beyond the
    /// reserve, on top of what is already on disk. Comparing the bytes written against the
    /// current free space alone counted them twice, and a session that started with 10 GB
    /// free stopped at about half of it, saying the phone was out of storage.
    ///
    /// `availableBytes` is nil when the volume will not say. The fixed options do not care —
    /// their ceiling is their own — and the open-ended one falls back to the largest fixed
    /// ceiling rather than running unbounded on an answer nobody gave.
    func byteCeiling(writtenBytes: Int = 0, availableBytes: Int64?) -> Int {
        switch self {
        case .twoHours: return 100 * Self.megabyte
        case .sixHours: return 300 * Self.megabyte
        case .twelveHours: return 600 * Self.megabyte
        case .untilStorageRunsOut:
            guard let availableBytes else { return 600 * Self.megabyte }
            let written = max(0, writtenBytes)
            let spare = max(0, availableBytes - Int64(Self.reserveBytes))
            return written + Int(min(spare, Int64(Int.max - written)))
        }
    }

    /// How much room must be free before a session may start, so a recording does not begin
    /// only to stop a minute later (Q-4).
    var minimumFreeBytes: Int {
        switch self {
        case .untilStorageRunsOut: Self.reserveBytes + Self.workingBytes
        case .twoHours, .sixHours, .twelveHours: byteCeiling(availableBytes: nil)
        }
    }

    /// The line under the picker, so the limit is never a mystery.
    var detail: String {
        let size = byteCeiling(availableBytes: nil).formatted(.byteCount(style: .file))
        switch self {
        case .twoHours, .sixHours, .twelveHours:
            return "Stops at \(title) or \(size), whichever comes first."
        case .untilStorageRunsOut:
            return """
                No time limit. Stops with \
                \(Self.reserveBytes.formatted(.byteCount(style: .file))) still free on this \
                iPhone, so a long journey is not cut short by the clock.
                """
        }
    }

    /// How full a running session is against whichever limit it will reach first, 0 to 1, so
    /// the recording bar can warn before it gets there (Q-4).
    func fraction(elapsed: TimeInterval, byteCount: Int, availableBytes: Int64?) -> Double {
        let ceiling = byteCeiling(writtenBytes: byteCount, availableBytes: availableBytes)
        let bySize = ceiling > 0 ? Double(byteCount) / Double(ceiling) : 1
        let byTime = duration.map { elapsed / $0 } ?? 0
        return min(1, max(0, max(bySize, byTime)))
    }

    /// Why a session stopped, for the message the bar puts up. Nil while it is still inside
    /// both limits.
    func reasonToStop(elapsed: TimeInterval, byteCount: Int, availableBytes: Int64?) -> String? {
        if byteCount >= byteCeiling(writtenBytes: byteCount, availableBytes: availableBytes) {
            switch self {
            case .untilStorageRunsOut:
                return """
                    This recording was saved because this iPhone is running out of storage. \
                    Readout keeps \(Self.reserveBytes.formatted(.byteCount(style: .file))) free.
                    """
            case .twoHours, .sixHours, .twelveHours:
                let size = byteCeiling(availableBytes: nil).formatted(.byteCount(style: .file))
                return "This recording reached Readout's \(size) limit and was saved there."
            }
        }
        if let duration, elapsed >= duration {
            return "This recording reached Readout's \(title) limit and was saved there."
        }
        return nil
    }
}
