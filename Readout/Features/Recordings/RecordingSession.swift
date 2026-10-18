import Foundation
import SwiftData

/// One saved recording. SwiftData keeps the metadata; the samples themselves live in CSV
/// files on disk, one per reading, in a folder named after `identifier` (R-61).
///
/// Nothing here leaves the phone: a session stays on the device until the user exports it,
/// and deleting the app deletes it with everything else in Application Support (R-57).
@Model
final class RecordingSession {
    /// Also the name of the folder holding this session's CSV files.
    var identifier: UUID = UUID()
    /// Auto-generated at the end of a recording, and renameable afterwards (R-42, R-43).
    var name: String = ""
    var startedAt: Date = Date.distantPast
    var duration: TimeInterval = 0
    var rateIdentifier: String = RecordingRate.medium.rawValue
    /// Set when the app left the foreground mid-recording (R-41).
    var isInterrupted: Bool = false
    var sampleCount: Int = 0
    var byteCount: Int = 0

    /// The per-reading summaries, as JSON. One blob keeps the schema flat — the samples are
    /// on disk anyway, so there is nothing here worth querying across sessions.
    private var tracksData: Data = Data()

    init(
        identifier: UUID,
        name: String,
        startedAt: Date,
        duration: TimeInterval,
        rate: RecordingRate,
        isInterrupted: Bool,
        tracks: [RecordedTrack]
    ) {
        self.identifier = identifier
        self.name = name
        self.startedAt = startedAt
        self.duration = duration
        self.rateIdentifier = rate.rawValue
        self.isInterrupted = isInterrupted
        self.sampleCount = tracks.reduce(0) { $0 + $1.sampleCount }
        self.byteCount = tracks.reduce(0) { $0 + $1.byteCount }
        self.tracksData = (try? JSONEncoder().encode(tracks)) ?? Data()
    }

    var tracks: [RecordedTrack] {
        get { (try? JSONDecoder().decode([RecordedTrack].self, from: tracksData)) ?? [] }
        set {
            tracksData = (try? JSONEncoder().encode(newValue)) ?? Data()
            sampleCount = newValue.reduce(0) { $0 + $1.sampleCount }
            byteCount = newValue.reduce(0) { $0 + $1.byteCount }
        }
    }

    var rate: RecordingRate {
        RecordingRate(rawValue: rateIdentifier) ?? .medium
    }

    var readings: [ReadingID] { tracks.map(\.reading) }

    var endedAt: Date { startedAt.addingTimeInterval(duration) }

    /// "12 s · 3 readings · 48 KB", the line under the name in the list (R-42).
    var listSummary: String {
        let duration = Duration.seconds(self.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow))
        let readings = tracks.count == 1 ? "1 reading" : "\(tracks.count) readings"
        let size = byteCount.formatted(.byteCount(style: .file))
        return "\(duration) · \(readings) · \(size)"
    }
}
