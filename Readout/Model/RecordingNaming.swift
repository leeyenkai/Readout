import Foundation

/// The names a recording gives itself: the session's own name (R-42), the file names it
/// exports under (R-44) and the elapsed time on the recording bar (R-40).
///
/// Pure string work, kept out of the service so the rules can be tested.
enum RecordingNaming {
    /// How many readings a session name lists before it says "and n more".
    static let listedReadings = 2

    /// The name a new session starts with: when it was recorded, then what it recorded.
    static func sessionName(startedAt: Date, readings: [ReadingID]) -> String {
        name(when: startedAt.formatted(date: .abbreviated, time: .shortened), readings: readings)
    }

    static func name(when: String, readings: [ReadingID]) -> String {
        let summary = readingSummary(readings)
        return summary.isEmpty ? when : "\(when) · \(summary)"
    }

    /// "Acceleration, Sound level" — or "Acceleration, Sound level and 2 more" once a session
    /// has more readings than a row can show.
    static func readingSummary(_ readings: [ReadingID], listing limit: Int = listedReadings) -> String {
        let names = readings.map { ReadingCatalog.descriptor($0).name }
        guard names.count > limit else { return names.joined(separator: ", ") }
        let listed = names.prefix(limit).joined(separator: ", ")
        return "\(listed) and \(names.count - limit) more"
    }

    /// `Readout-2026-10-18-1430-accel.csv`: the date and time are in the file name because the
    /// share sheet sends the files on their own, without the folder they sat in (R-44).
    static func fileName(prefix: String, startedAt: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "Readout-\(formatter.string(from: startedAt))-\(prefix).csv"
    }

    /// Elapsed time as m:ss, growing to h:mm:ss after an hour (R-40).
    static func elapsedText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let (hours, minutes, remainder) = (total / 3_600, (total % 3_600) / 60, total % 60)
        let paddedSeconds = String(format: "%02d", remainder)
        guard hours > 0 else { return "\(minutes):\(paddedSeconds)" }
        return "\(hours):\(String(format: "%02d", minutes)):\(paddedSeconds)"
    }

    /// "3 samples" / "1 sample", for the recording bar and the session list.
    static func sampleCountText(_ count: Int) -> String {
        count == 1 ? "1 sample" : "\(count.formatted(.number.grouping(.automatic))) samples"
    }
}
