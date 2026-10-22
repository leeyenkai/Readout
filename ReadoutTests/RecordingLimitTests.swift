import Foundation
import Testing
@testable import Readout

/// How far a session may run before it stops itself (Q-4, R-80).
@Suite("Recording limits")
struct RecordingLimitTests {
    private let gigabyte: Int64 = 1_000_000_000

    @Test("Two hours is still the default")
    func defaultIsUnchanged() {
        #expect(RecordingLimit.default == .twoHours)
        #expect(RecordingLimit.twoHours.duration == TimeInterval(2 * 60 * 60))
        #expect(RecordingLimit.twoHours.byteCeiling(availableBytes: nil) == 100_000_000)
    }

    @Test("Every limit says what it is")
    func everyLimitIsDescribed() {
        for limit in RecordingLimit.allCases {
            #expect(!limit.title.isEmpty)
            #expect(!limit.detail.isEmpty)
        }
    }

    @Test("A longer limit carries a larger storage ceiling with it")
    func ceilingsGrowWithTheClock() {
        let ordered: [RecordingLimit] = [.twoHours, .sixHours, .twelveHours]
        let ceilings = ordered.map { $0.byteCeiling(availableBytes: nil) }
        #expect(ceilings == ceilings.sorted())
        #expect(Set(ceilings).count == ceilings.count)
    }

    // MARK: - Running until the storage runs out

    @Test("The open-ended limit has no clock at all")
    func openEndedHasNoClock() {
        #expect(RecordingLimit.untilStorageRunsOut.duration == nil)
        let fraction = RecordingLimit.untilStorageRunsOut.fraction(
            elapsed: 60 * 60 * 24,
            byteCount: 0,
            availableBytes: 10 * gigabyte
        )
        #expect(fraction == 0)
    }

    @Test("It leaves the reserve free on the volume")
    func openEndedKeepsTheReserve() {
        let ceiling = RecordingLimit.untilStorageRunsOut.byteCeiling(availableBytes: 2 * gigabyte)
        #expect(ceiling == Int(2 * gigabyte) - RecordingLimit.reserveBytes)
    }

    @Test("A volume already inside the reserve offers no room at all")
    func openEndedOnAFullDisk() {
        let ceiling = RecordingLimit.untilStorageRunsOut.byteCeiling(availableBytes: 1_000)
        #expect(ceiling == 0)
        // And a session on such a volume is over before it starts, rather than dividing by it.
        let fraction = RecordingLimit.untilStorageRunsOut.fraction(
            elapsed: 0,
            byteCount: 0,
            availableBytes: 1_000
        )
        #expect(fraction == 1)
    }

    /// The volume will not always say how much room it has. Running unbounded on an answer
    /// nobody gave is the one outcome worth ruling out.
    @Test("With no answer from the volume the open-ended limit still has a ceiling")
    func openEndedWithoutAnAnswer() {
        let ceiling = RecordingLimit.untilStorageRunsOut.byteCeiling(availableBytes: nil)
        #expect(ceiling == RecordingLimit.twelveHours.byteCeiling(availableBytes: nil))
    }

    @Test("A fixed limit ignores how much room the volume has")
    func fixedLimitsIgnoreTheVolume() {
        for limit in [RecordingLimit.twoHours, .sixHours, .twelveHours] {
            #expect(
                limit.byteCeiling(availableBytes: 500 * gigabyte)
                    == limit.byteCeiling(availableBytes: nil)
            )
        }
    }

    // MARK: - Stopping

    @Test("A session inside both limits has no reason to stop")
    func noReasonToStopYet() {
        let reason = RecordingLimit.twoHours.reasonToStop(
            elapsed: 60,
            byteCount: 1_000,
            availableBytes: 10 * gigabyte
        )
        #expect(reason == nil)
    }

    @Test("Reaching either limit stops the session and says which one")
    func stopsAtEitherLimit() throws {
        let byTime = try #require(RecordingLimit.twoHours.reasonToStop(
            elapsed: 2 * 60 * 60,
            byteCount: 0,
            availableBytes: 10 * gigabyte
        ))
        #expect(byTime.contains("2 hours"))

        let bySize = try #require(RecordingLimit.twoHours.reasonToStop(
            elapsed: 1,
            byteCount: 100_000_000,
            availableBytes: 10 * gigabyte
        ))
        #expect(bySize.contains("100 MB"))

        let byStorage = try #require(RecordingLimit.untilStorageRunsOut.reasonToStop(
            elapsed: 60 * 60 * 20,
            byteCount: 900_000_000,
            availableBytes: Int64(RecordingLimit.reserveBytes)
        ))
        #expect(byStorage.contains("storage"))
    }

    /// The free space the volume reports already has the session's own files taken out of
    /// it. Counting them again stopped a session at about half the room it had.
    @Test("Bytes already written are not counted against the free space twice")
    func writtenBytesCountOnce() {
        let written = 900_000_000
        let available = Int64(RecordingLimit.reserveBytes) + 800_000_000
        let limit = RecordingLimit.untilStorageRunsOut
        #expect(limit.reasonToStop(elapsed: 60 * 60 * 20, byteCount: written, availableBytes: available) == nil)
        #expect(limit.byteCeiling(writtenBytes: written, availableBytes: available) == 1_700_000_000)
        let fraction = limit.fraction(elapsed: 0, byteCount: written, availableBytes: available)
        #expect(abs(fraction - 900.0 / 1_700.0) < 0.0001)
    }

    @Test("How full a session is never leaves nought to one")
    func fractionStaysInRange() {
        let elapsedCases: [TimeInterval] = [0, 60, 60 * 60 * 48]
        let byteCases: [Int] = [0, 10_000, 5_000_000_000]
        for limit in RecordingLimit.allCases {
            for elapsed in elapsedCases {
                for bytes in byteCases {
                    let fraction = limit.fraction(
                        elapsed: elapsed,
                        byteCount: bytes,
                        availableBytes: 10 * gigabyte
                    )
                    #expect(fraction >= 0 && fraction <= 1)
                }
            }
        }
    }

    @Test("A session must have room to finish before it may start")
    func freeSpaceNeededToStart() {
        #expect(RecordingLimit.twoHours.minimumFreeBytes == 100_000_000)
        #expect(RecordingLimit.twelveHours.minimumFreeBytes == 600_000_000)
        // The open-ended one needs the reserve it promises to leave, and room to work in.
        #expect(RecordingLimit.untilStorageRunsOut.minimumFreeBytes > RecordingLimit.reserveBytes)
    }

    @Test("The chosen limit survives a new AppSettings reading the same defaults")
    @MainActor
    func limitPersists() {
        let defaults = throwawayDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.recordingLimit == .twoHours)

        settings.recordingLimit = .untilStorageRunsOut
        #expect(AppSettings(defaults: defaults).recordingLimit == .untilStorageRunsOut)
    }
}
