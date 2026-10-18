import Foundation
import Testing
@testable import Readout

@Suite("CSV format")
struct CSVTableTests {
    /// The moment SPEC §8.4's example starts: 2026-10-18T14:30:00 in +08:00.
    private static let timeZone = TimeZone(secondsFromGMT: 8 * 3_600)!

    private static let start: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 18
        components.hour = 14
        components.minute = 30
        components.second = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }()

    private func table(_ reading: ReadingID, timeZone: TimeZone = CSVTableTests.timeZone) -> CSVTable {
        CSVTable(
            descriptor: ReadingCatalog.descriptor(reading),
            startedAt: Self.start,
            timeZone: timeZone
        )
    }

    @Test("The header matches the spec's example exactly")
    func headerMatchesSpec() {
        #expect(table(.acceleration).header == "timestamp,elapsed_s,accel_x_g,accel_y_g,accel_z_g")
    }

    @Test("Rows match the spec's example exactly")
    func rowsMatchSpec() {
        let table = table(.acceleration)
        let first = SensorSample(time: Self.start, values: [0.012, -0.981, 0.034])
        let second = SensorSample(time: Self.start.addingTimeInterval(0.1), values: [0.015, -0.979, 0.031])
        let third = SensorSample(time: Self.start.addingTimeInterval(0.2), values: [0.011, -0.983, 0.036])
        #expect(table.row(first) == "2026-10-18T14:30:00.000+08:00,0.000,0.012,-0.981,0.034")
        #expect(table.row(second) == "2026-10-18T14:30:00.100+08:00,0.100,0.015,-0.979,0.031")
        #expect(table.row(third) == "2026-10-18T14:30:00.200+08:00,0.200,0.011,-0.983,0.036")
    }

    @Test("Timestamps carry the recording phone's own offset")
    func timeZoneOffset() {
        let newYork = table(.acceleration, timeZone: TimeZone(secondsFromGMT: -5 * 3_600)!)
        #expect(newYork.timestamp(Self.start) == "2026-10-18T01:30:00.000-05:00")
    }

    @Test("Milliseconds are always three digits")
    func milliseconds() {
        let table = table(.acceleration)
        #expect(table.timestamp(Self.start.addingTimeInterval(0.004)) == "2026-10-18T14:30:00.004+08:00")
        #expect(table.timestamp(Self.start.addingTimeInterval(1.5)) == "2026-10-18T14:30:01.500+08:00")
    }

    @Test("A single-channel reading names its column after the reading and its unit")
    func singleChannelColumns() {
        #expect(table(.soundLevel).valueColumns == ["sound_level_dB"])
        #expect(table(.airPressure).valueColumns == ["air_pressure_hPa"])
        #expect(table(.heading).valueColumns == ["heading_deg"])
        #expect(table(.light).valueColumns == ["light_lux"])
        #expect(table(.relativeAltitude).valueColumns == ["relative_altitude_m"])
    }

    @Test("A multi-channel reading names the channel, and never repeats a word")
    func multiChannelColumns() {
        #expect(table(.orientation).valueColumns == ["orientation_pitch_deg", "orientation_roll_deg", "orientation_yaw_deg"])
        #expect(table(.coordinates).valueColumns == ["coordinates_latitude_deg", "coordinates_longitude_deg"])
        #expect(table(.locationAccuracy).valueColumns == ["location_accuracy_horizontal_m", "location_accuracy_vertical_m"])
        // "activity" + "steps" + the unit "steps" is written once, not twice.
        #expect(table(.activity).valueColumns == ["activity_steps", "activity_distance_m", "activity_floors"])
        #expect(table(.cadence).valueColumns == ["cadence_steps_min", "cadence_pace_s_km"])
    }

    @Test("A discrete reading gets a state column")
    func discreteReadingHasState() {
        let table = table(.proximity)
        #expect(table.header == "timestamp,elapsed_s,proximity,state")
        let sample = SensorSample(time: Self.start, values: [1], state: "Near")
        #expect(table.row(sample) == "2026-10-18T14:30:00.000+08:00,0.000,1,Near")
    }

    @Test("A state with a comma or a quote is quoted, as RFC 4180 asks")
    func escaping() {
        #expect(CSVTable.escaped("Nominal") == "Nominal")
        #expect(CSVTable.escaped("Serious, throttling") == "\"Serious, throttling\"")
        #expect(CSVTable.escaped("25\" rule") == "\"25\"\" rule\"")
    }

    @Test("Values keep up to six decimals with no padding")
    func numberFormatting() {
        #expect(CSVTable.number(0.012) == "0.012")
        #expect(CSVTable.number(-0.981) == "-0.981")
        #expect(CSVTable.number(1_013.25) == "1013.25")
        #expect(CSVTable.number(0) == "0")
        #expect(CSVTable.number(-0.0000001) == "0")
        #expect(CSVTable.number(1.3521098765) == "1.35211")
    }

    @Test("A missing or non-finite value leaves the cell empty rather than writing nan")
    func missingValues() {
        #expect(CSVTable.number(nil) == "")
        #expect(CSVTable.number(.nan) == "")
        #expect(CSVTable.number(.infinity) == "")
        let row = table(.locationAccuracy).row(SensorSample(time: Self.start, values: [6.5]))
        #expect(row == "2026-10-18T14:30:00.000+08:00,0.000,6.5,")
    }

    @Test("Elapsed seconds always carry three decimals")
    func elapsedFormatting() {
        #expect(CSVTable.elapsed(0) == "0.000")
        #expect(CSVTable.elapsed(0.1) == "0.100")
        #expect(CSVTable.elapsed(12.3456) == "12.346")
        #expect(CSVTable.elapsed(.nan) == "")
    }

    @Test("Every reading in the catalog produces unique, ASCII column names")
    func everyReadingHasUsableColumns() {
        for descriptor in ReadingCatalog.all {
            let columns = CSVTable(descriptor: descriptor, startedAt: Self.start).valueColumns
            #expect(columns.count == descriptor.channels.count + (descriptor.kind == .discrete ? 1 : 0))
            #expect(Set(columns).count == columns.count, "\(descriptor.id.rawValue) repeats a column name")
            for column in columns {
                #expect(!column.isEmpty)
                #expect(column.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") })
            }
        }
    }
}
