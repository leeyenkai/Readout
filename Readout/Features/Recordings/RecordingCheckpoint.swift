import Foundation

/// A running recording's metadata, kept beside its CSV files so a session the app never got
/// to save is not lost.
///
/// A recording's rows are flushed to disk as they arrive, but the `RecordingSession` that
/// describes them is only inserted when the recording stops. If the app is killed first — by
/// jetsam, by a crash, by the user force-quitting — the rows are on disk with nothing pointing
/// at them, and the next launch used to delete them as orphans. The checkpoint is what the
/// next launch reads instead, so the recording comes back marked interrupted (R-41, R-57).
struct RecordingCheckpoint: Codable, Hashable, Sendable {
    var identifier: UUID
    var startedAt: Date
    var duration: TimeInterval
    var rate: RecordingRate
    var tracks: [RecordedTrack]

    /// What a recovered session is called, so it is obvious in the list why it is short.
    var recoveredName: String {
        RecordingNaming.sessionName(startedAt: startedAt, readings: tracks.map(\.reading))
    }
}
