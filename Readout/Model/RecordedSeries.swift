import Foundation

/// One reading's samples read back from its CSV file, for the chart in the session view
/// (R-43).
///
/// The file on disk is the only copy of a session's samples, so this is the reverse of
/// `CSVTable`: pure, and tested by writing a table and reading it back.
struct RecordedSeries: Sendable, Equatable {
    /// Seconds since the recording started, from the `elapsed_s` column.
    var elapsed: [Double]
    /// One array per value column, aligned with the reading's channels.
    var channels: [[Double]]

    var isEmpty: Bool { elapsed.isEmpty }

    static let empty = RecordedSeries(elapsed: [], channels: [])

    /// Reads the numeric columns of a CSV written by `CSVTable`. Rows that are short, blank
    /// or unparseable are skipped rather than failing the whole file: a session that was
    /// interrupted mid-row should still draw.
    init(csv: String) {
        var elapsed: [Double] = []
        var columns: [[Double]] = []
        for (index, line) in csv.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            // The header names the columns; the first field of a row is the timestamp, which
            // the chart does not need because every row carries its elapsed seconds.
            guard index > 0 else { continue }
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 1, let seconds = Double(fields[1]) else { continue }
            elapsed.append(seconds)
            for (column, field) in fields.dropFirst(2).enumerated() {
                if columns.count == column { columns.append([]) }
                columns[column].append(Double(field) ?? .nan)
            }
        }
        self.elapsed = elapsed
        self.channels = columns
    }

    init(elapsed: [Double], channels: [[Double]]) {
        self.elapsed = elapsed
        self.channels = channels
    }

    /// Points for one channel, thinned to at most `limit` of them. A ten-minute recording at
    /// 50 Hz is 30,000 rows, which no 150-point-tall chart needs.
    func points(channel: Int, limit: Int = 400) -> [RecordedPoint] {
        guard channels.indices.contains(channel) else { return [] }
        let values = channels[channel]
        let count = min(elapsed.count, values.count)
        guard count > 0 else { return [] }
        let step = max(1, count / max(1, limit))
        return stride(from: 0, to: count, by: step).compactMap { index in
            let value = values[index]
            guard value.isFinite else { return nil }
            return RecordedPoint(elapsed: elapsed[index], value: value)
        }
    }
}

/// One point of a recorded channel, for the session view's chart.
struct RecordedPoint: Sendable, Identifiable, Equatable {
    let elapsed: Double
    let value: Double

    var id: Double { elapsed }
}
