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
        var accumulator = Accumulator(maximumRows: .max)
        for (index, line) in csv.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            guard index > 0 else { continue }
            accumulator.add(line)
        }
        self = accumulator.series
    }

    /// Reads a session's CSV straight from disk, a block at a time.
    ///
    /// A two-hour recording is hundreds of thousands of rows, and loading the file into a
    /// `String` first put tens of megabytes on the heap per reading before a single point was
    /// drawn. Rows are parsed as they arrive and thinned as they accumulate, so the memory
    /// this holds depends on the chart, not on the length of the recording.
    init?(contentsOf url: URL, maximumRows: Int = 3_200) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var accumulator = Accumulator(maximumRows: maximumRows)
        var remainder = Data()
        var isFirstLine = true
        let newline = UInt8(ascii: "\n")

        while let block = try? handle.read(upToCount: 64 * 1_024), !block.isEmpty {
            remainder.append(block)
            while let end = remainder.firstIndex(of: newline) {
                let line = remainder[remainder.startIndex..<end]
                remainder = remainder[remainder.index(after: end)...]
                // The header names the columns; it carries no values.
                if isFirstLine {
                    isFirstLine = false
                } else if let text = String(data: line, encoding: .utf8) {
                    accumulator.add(text[...])
                }
            }
            remainder = Data(remainder)
        }
        if !isFirstLine, !remainder.isEmpty, let text = String(data: remainder, encoding: .utf8) {
            accumulator.add(text[...])
        }
        self = accumulator.series
    }

    init(elapsed: [Double], channels: [[Double]]) {
        self.elapsed = elapsed
        self.channels = channels
    }

    /// The route a session recorded, as latitude and longitude pairs in the order they were
    /// logged (R-76).
    ///
    /// The two channels are paired here rather than through `points(channel:)`, which thins
    /// each channel on its own: were the two ever to come out at different lengths they would
    /// be thinned at different strides, and the pairs would stop belonging to each other —
    /// which on a map is not a rough line but a wrong one.
    ///
    /// A fix Core Location never produced is written as an empty cell and read back as NaN,
    /// and a coordinate outside the globe is a corrupt row; both are dropped rather than
    /// drawn.
    func coordinates(latitude: Int = 0, longitude: Int = 1, limit: Int = 2_000) -> [RecordedCoordinate] {
        guard channels.indices.contains(latitude), channels.indices.contains(longitude) else {
            return []
        }
        let latitudes = channels[latitude]
        let longitudes = channels[longitude]
        let count = min(elapsed.count, min(latitudes.count, longitudes.count))
        guard count > 0 else { return [] }

        let step = max(1, count / max(1, limit))
        var route: [RecordedCoordinate] = []
        route.reserveCapacity(min(count, limit) + 1)
        for index in Swift.stride(from: 0, to: count, by: step) {
            let point = RecordedCoordinate(
                index: index,
                elapsed: elapsed[index],
                latitude: latitudes[index],
                longitude: longitudes[index]
            )
            guard point.isValid else { continue }
            route.append(point)
        }
        return route
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

private extension RecordedSeries {
    /// Parses rows into columns, halving what it keeps whenever it grows past its budget.
    ///
    /// Halving rather than dropping the tail, so the shape of a long recording survives: the
    /// chart sees the whole session at a coarser spacing instead of the first few minutes of
    /// it at full detail.
    struct Accumulator {
        let maximumRows: Int

        private var elapsed: [Double] = []
        private var columns: [[Double]] = []
        /// Rows between the ones kept. Doubles each time the budget is reached.
        private var stride = 1
        private var seen = 0

        init(maximumRows: Int) {
            self.maximumRows = maximumRows
        }

        mutating func add(_ line: Substring) {
            defer { seen += 1 }
            guard seen % stride == 0 else { return }
            // The first field of a row is the timestamp, which the chart does not need
            // because every row carries its elapsed seconds.
            let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            guard fields.count > 1, let seconds = Double(fields[1]) else { return }
            elapsed.append(seconds)
            for (column, field) in fields.dropFirst(2).enumerated() {
                if columns.count == column { columns.append([]) }
                columns[column].append(Double(field) ?? .nan)
            }
            if elapsed.count >= maximumRows {
                halve()
            }
        }

        private mutating func halve() {
            elapsed = Self.everyOther(elapsed)
            columns = columns.map(Self.everyOther)
            stride *= 2
        }

        private static func everyOther(_ values: [Double]) -> [Double] {
            Swift.stride(from: 0, to: values.count, by: 2).map { values[$0] }
        }

        var series: RecordedSeries {
            RecordedSeries(elapsed: elapsed, channels: columns)
        }
    }
}

/// One point of a recorded channel, for the session view's chart.
struct RecordedPoint: Sendable, Identifiable, Equatable {
    let elapsed: Double
    let value: Double

    var id: Double { elapsed }
}

/// One fix along a recorded route (R-76).
struct RecordedCoordinate: Sendable, Identifiable, Equatable {
    /// The row it came from, which is what makes it unique: two fixes a second apart can
    /// easily share an elapsed time once the series has been thinned.
    let index: Int
    let elapsed: Double
    let latitude: Double
    let longitude: Double

    var id: Int { index }

    /// Whether this is a position at all. Core Location writes an unknown one as NaN, and
    /// anything off the globe is a corrupt row.
    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}
