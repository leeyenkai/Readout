import Foundation

/// One reading's CSV, exactly as SPEC §8.4 lays it out (R-45).
///
/// ```csv
/// timestamp,elapsed_s,accel_x_g,accel_y_g,accel_z_g
/// 2026-10-18T14:30:00.000+08:00,0.000,0.012,-0.981,0.034
/// ```
///
/// This is a string function of a descriptor, a start time and a time zone: nothing here
/// touches a file or a sensor, so `ReadoutTests` can hold the format to the spec without
/// hardware. Values are written in the unit they are stored in — metric base units — so a
/// file means the same thing whatever the exporting phone was set to show.
struct CSVTable {
    let descriptor: ReadingDescriptor
    let startedAt: Date

    private let formatter: DateFormatter

    init(descriptor: ReadingDescriptor, startedAt: Date, timeZone: TimeZone = .current) {
        self.descriptor = descriptor
        self.startedAt = startedAt
        let formatter = DateFormatter()
        // Fixed format, POSIX locale: this output is read by machines, not people, so it must
        // not follow the phone's region the way `ValueFormatting` does.
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        self.formatter = formatter
    }

    // MARK: - Columns

    /// The column names after `timestamp` and `elapsed_s`: one per value, with its unit, plus
    /// a `state` column where the reading is a discrete one such as proximity.
    var valueColumns: [String] {
        var columns = descriptor.channels.map { Self.columnName(descriptor: descriptor, channel: $0) }
        if descriptor.kind == .discrete {
            columns.append("state")
        }
        return columns
    }

    var header: String {
        (["timestamp", "elapsed_s"] + valueColumns).joined(separator: ",")
    }

    /// `accel_x_g`, `sound_level_dB`, `cadence_pace_s_km`: the reading's stem, the channel
    /// where there is more than one, then the unit. A part that repeats the one before it is
    /// dropped, so `activity` + `steps` + `steps` is written `activity_steps`.
    static func columnName(descriptor: ReadingDescriptor, channel: ReadingChannel) -> String {
        var parts = [descriptor.csvPrefix]
        if descriptor.channels.count > 1 {
            parts.append(ReadingDescriptor.snakeCased(channel.name))
        }
        parts.append(channel.unit.csvSymbol)
        return parts
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, part in
                guard result.last?.lowercased() != part.lowercased() else { return }
                result.append(part)
            }
            .joined(separator: "_")
    }

    // MARK: - Rows

    func row(_ sample: SensorSample) -> String {
        var fields = [timestamp(sample.time), Self.elapsed(sample.time.timeIntervalSince(startedAt))]
        for index in descriptor.channels.indices {
            fields.append(Self.number(sample.value(index)))
        }
        if descriptor.kind == .discrete {
            fields.append(Self.escaped(sample.state ?? ""))
        }
        return fields.joined(separator: ",")
    }

    func timestamp(_ time: Date) -> String {
        formatter.string(from: time)
    }

    /// Seconds since the recording started, always to three decimal places, as the spec shows.
    static func elapsed(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "" }
        return String(format: "%.3f", seconds)
    }

    /// A value with up to six decimal places and no padding, so 0.012 is written `0.012`.
    /// A missing or non-finite value leaves the cell empty rather than writing `nan`, which
    /// every spreadsheet reads as text.
    static func number(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "" }
        var text = String(format: "%.6f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// RFC 4180 quoting, for the state of a discrete reading.
    static func escaped(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"\(field.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
