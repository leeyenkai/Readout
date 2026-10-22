import Foundation
import Observation
import SwiftData
import UIKit

/// Runs a recording: takes samples from `SensorHub` at the chosen rate, writes them to CSV
/// as they arrive, and saves the session when it stops (R-6, R-37–R-41).
///
/// Samples come from the hub's tap rather than from the chart history, because that history
/// decimates to about 10 Hz and a High recording wants 50 (R-39, R-65). Recording is
/// foreground-only in v1: `RootView` stops it when the app goes away (R-41).
@MainActor
@Observable
final class RecordingService {
    /// When the running recording started, or nil when nothing is recording.
    private(set) var startedAt: Date?
    private(set) var rate: RecordingRate = .medium
    private(set) var readings: [ReadingID] = []
    /// Published on the tick rather than per sample, so the recording bar redraws a few times
    /// a second instead of fifty.
    private(set) var sampleCount = 0
    private(set) var elapsed: TimeInterval = 0
    /// What the session has written so far, for the limit and the bar's warning (Q-4).
    private(set) var byteCount = 0
    /// The journey so far, where the session is logging coordinates, for the live view's
    /// route (R-76, R-79). Thinned as it grows; the CSV keeps every fix regardless.
    private(set) var route: [RecordedCoordinate] = []

    /// Set when a recording could not start, was cut short, or could not be saved.
    var failure: RecordingFailure?

    /// The recording most recently saved, for the brief "Saved" confirmation. Without it a
    /// recording ended with nothing but a haptic and a bar sliding away.
    private(set) var lastSaved: SavedRecording?

    /// False when SwiftData could not open its store and the app fell back to an in-memory
    /// one. Sessions cannot be listed or saved, and — crucially — nothing on disk may be
    /// treated as an orphan, because the empty store knows about none of it.
    let isStorePersistent: Bool

    let store: RecordingStore

    private let hub: SensorHub
    private let context: ModelContext
    private var writers: [RecordingTrackWriter] = []
    /// One per reading being recorded, released together when the session stops (R-64).
    private var leases: [SensorLease] = []
    private var sessionIdentifier: UUID?
    private var timer: Timer?
    private var ticksSinceCheckpoint = 0
    /// Fixes between the ones the drawn route keeps. Doubles each time it fills up.
    private var routeStride = 1
    private var routeFixesSeen = 0

    /// How often the bar's numbers are refreshed and the row buffers are flushed.
    private static let tickInterval: TimeInterval = 0.5
    /// Every two seconds. The rows themselves are flushed on every tick; this is only the
    /// metadata a recovered session is rebuilt from, so a crash costs at most this much of it.
    private static let ticksPerCheckpoint = 4

    /// How many fixes the drawn route holds before it is halved.
    private static let maximumRouteFixes = 2_000

    /// The limit the running session was started under, so changing the setting mid-recording
    /// cannot move the goalposts under a session already in progress (Q-4, R-80).
    private(set) var limit: RecordingLimit = .default

    /// What will happen to the running session when Readout leaves the foreground (R-82).
    /// Worked out once, as the session starts, from what it records and what it is allowed.
    private(set) var backgroundVerdict: BackgroundRecording.Verdict = .stopsWithoutLocation
    /// The volume's free space, re-read occasionally rather than on every tick: it is a
    /// `resourceValues` call, and the open-ended limit is the only thing that needs it.
    private var availableBytes: Int64?

    /// Where the chosen limit is read from when a session starts.
    private let settings: AppSettings

    init(
        hub: SensorHub,
        store: RecordingStore,
        context: ModelContext,
        settings: AppSettings,
        isStorePersistent: Bool = true
    ) {
        self.hub = hub
        self.store = store
        self.context = context
        self.settings = settings
        self.isStorePersistent = isStorePersistent
        hub.sampleObserver = { [weak self] reading, sample in
            self?.receive(reading, sample)
        }
    }

    var isRecording: Bool { startedAt != nil }

    /// Whether the running session survives Readout going to the background (R-82).
    var continuesInBackground: Bool { isRecording && backgroundVerdict.continuesInBackground }

    /// What would happen to a session recording `readings`, for the New Recording sheet to
    /// say before anything is started.
    func backgroundVerdict(for readings: some Collection<ReadingID>) -> BackgroundRecording.Verdict {
        guard hub.canRecordInBackground else { return .stopsWithoutLocation }
        return BackgroundRecording.verdict(
            for: readings,
            isLocationGranted: hub.permissions.status(of: .locationWhenInUse).isGranted
        )
    }

    func isRecording(_ reading: ReadingID) -> Bool {
        isRecording && readings.contains(reading)
    }

    // MARK: - Running a recording

    /// Starts recording the given readings, in catalog order. Any permission they need has
    /// already been asked for by the New Recording sheet (R-38).
    func start(readings chosen: [ReadingID], rate: RecordingRate) {
        guard !isRecording else { return }
        let ordered = ReadingCatalog.all.map(\.id).filter(chosen.contains)
        guard !ordered.isEmpty else { return }

        guard isStorePersistent else {
            report(.init(kind: .couldNotStart, message: """
                Readout cannot open its recordings store, so a new recording could not be \
                started. Restarting the app usually clears this.
                """))
            return
        }
        // The limit is fixed for the life of the session: changing the setting while one runs
        // should not move the goalposts under it (Q-4, R-80).
        let limit = settings.recordingLimit
        let available = store.availableBytes()
        if let available, available < Int64(limit.minimumFreeBytes) {
            report(.init(kind: .couldNotStart, message: """
                There is not enough free space on this iPhone for a recording. A \
                \(limit.title.lowercased()) session needs room for \
                \(limit.minimumFreeBytes.formatted(.byteCount(style: .file))).
                """))
            return
        }

        let identifier = UUID()
        let start = Date.now
        do {
            let folder = try store.createFolder(for: identifier)
            writers = try ordered.map { reading in
                try RecordingTrackWriter(
                    descriptor: ReadingCatalog.descriptor(reading),
                    folder: folder,
                    startedAt: start,
                    rate: rate
                )
            }
        } catch {
            writers = []
            store.deleteFolder(for: identifier)
            report(.init(kind: .couldNotStart, message: "Readout could not make room for this recording on the device."))
            return
        }

        sessionIdentifier = identifier
        startedAt = start
        self.rate = rate
        self.limit = limit
        backgroundVerdict = backgroundVerdict(for: ordered)
        self.availableBytes = available
        self.readings = ordered
        sampleCount = 0
        elapsed = 0
        byteCount = 0
        ticksSinceCheckpoint = 0
        route = []
        routeStride = 1
        routeFixesSeen = 0
        writeCheckpoint()
        for reading in ordered {
            leases.append(hub.activate(reading, rate: rate.activationRate))
        }
        // The screen stays awake for as long as the recording runs (R-40).
        UIApplication.shared.isIdleTimerDisabled = true
        // And, where the session qualifies, Core Location holds the app alive past the point
        // the screen goes off (R-82).
        hub.setBackgroundLocationUpdates(backgroundVerdict.continuesInBackground)
        startTicking()
    }

    /// Stops the recording and saves it. `interrupted` marks a session the app left the
    /// foreground in the middle of (R-41).
    func stop(interrupted: Bool = false) {
        stop(interrupted: interrupted, limit: nil)
    }

    private func stop(interrupted: Bool, limit: String?) {
        guard let startedAt, let identifier = sessionIdentifier else { return }
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        // Given back the moment the recording ends: holding it would keep the app alive, and
        // the blue indicator lit, for a user who is no longer recording anything (R-82).
        hub.setBackgroundLocationUpdates(false)
        leases.forEach(hub.release)
        leases = []
        hub.stopKeptReadings()

        let tracks = writers.map { $0.finish() }
        let failedToWrite = writers.contains { $0.hasFailed }
        let droppedSamples = writers.reduce(0) { $0 + $1.droppedSamples }
        let duration = Date.now.timeIntervalSince(startedAt)
        let recorded = tracks.filter { $0.sampleCount > 0 }
        writers = []

        if recorded.isEmpty {
            // Nothing arrived — a recording stopped within a moment of starting, or every
            // reading stayed silent. An empty session is clutter, so it is dropped — but said
            // so, rather than leaving somebody looking for a recording that was never kept.
            store.deleteFolder(for: identifier)
            report(.init(kind: .nothingRecorded, message: """
                No samples arrived before the recording stopped, so there was nothing to keep.
                """))
        } else {
            save(
                identifier: identifier,
                startedAt: startedAt,
                duration: duration,
                tracks: recorded,
                isInterrupted: interrupted
            )
        }
        store.removeCheckpoint(for: identifier)
        if let limit {
            report(.init(kind: .stoppedAtLimit, message: limit))
        }
        if failedToWrite {
            report(.init(kind: .samplesDropped, message: """
                The device refused some writes, so \(droppedSamples.formatted()) \
                \(droppedSamples == 1 ? "sample is" : "samples are") missing from this recording.
                """))
        }

        self.startedAt = nil
        sessionIdentifier = nil
        readings = []
        elapsed = 0
        byteCount = 0
        route = []
        backgroundVerdict = .stopsWithoutLocation
    }

    /// Keeps the most serious thing that went wrong. A session that had to be discarded
    /// should not be reported as merely short because a later, milder failure overwrote it.
    private func report(_ candidate: RecordingFailure) {
        guard let existing = failure else {
            failure = candidate
            return
        }
        if candidate.kind > existing.kind {
            failure = candidate
        }
    }

    private func save(
        identifier: UUID,
        startedAt: Date,
        duration: TimeInterval,
        tracks: [RecordedTrack],
        isInterrupted: Bool
    ) {
        let session = RecordingSession(
            identifier: identifier,
            name: RecordingNaming.sessionName(startedAt: startedAt, readings: tracks.map(\.reading)),
            startedAt: startedAt,
            duration: duration,
            rate: rate,
            isInterrupted: isInterrupted,
            tracks: tracks
        )
        context.insert(session)
        do {
            try context.save()
            lastSaved = SavedRecording(identifier: identifier, name: session.name)
        } catch {
            context.delete(session)
            store.deleteFolder(for: identifier)
            report(.init(kind: .discarded, message: "This recording could not be saved, so it has been discarded."))
        }
    }

    private func receive(_ reading: ReadingID, _ sample: SensorSample) {
        // Providers replay their last value so a freshly opened view is not blank, and a
        // location fix can be minutes old. Recording it would write a row timestamped before
        // the session started, with a negative `elapsed_s` (R-45).
        guard let startedAt, sample.time >= startedAt else { return }
        guard let writer = writers.first(where: { $0.reading == reading }) else { return }
        writer.receive(sample)
        if reading == .coordinates {
            trackRoute(sample, startedAt: startedAt)
        }
    }

    /// Keeps the journey so far, so the live view can draw it as it happens (R-76, R-79).
    ///
    /// Thinned as it grows, the same way a finished session's series is: a route being
    /// watched on screen wants the shape of the journey, not every fix of a twelve-hour one.
    /// The CSV on disk keeps all of them regardless — this is only what is drawn.
    private func trackRoute(_ sample: SensorSample, startedAt: Date) {
        guard sample.values.count >= 2 else { return }
        defer { routeFixesSeen += 1 }
        guard routeFixesSeen % routeStride == 0 else { return }

        let fix = RecordedCoordinate(
            index: routeFixesSeen,
            elapsed: sample.time.timeIntervalSince(startedAt),
            latitude: sample.values[0],
            longitude: sample.values[1]
        )
        guard fix.isValid else { return }
        route.append(fix)
        if route.count >= Self.maximumRouteFixes {
            route = stride(from: 0, to: route.count, by: 2).map { route[$0] }
            routeStride *= 2
        }
    }

    private func startTicking() {
        let timer = Timer(timeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
        // `.common` so the bar keeps counting while a list is being scrolled.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date.now.timeIntervalSince(startedAt)
        for writer in writers {
            writer.flush()
        }
        sampleCount = writers.reduce(0) { $0 + $1.sampleCount }
        byteCount = writers.reduce(0) { $0 + $1.byteCount }

        ticksSinceCheckpoint += 1
        if ticksSinceCheckpoint >= Self.ticksPerCheckpoint {
            ticksSinceCheckpoint = 0
            writeCheckpoint()
            // Only the open-ended limit depends on the volume, and only it is worth
            // re-reading: another app can fill the disk while a long session runs.
            if limit == .untilStorageRunsOut {
                availableBytes = store.availableBytes()
            }
        }

        if let reason = limit.reasonToStop(
            elapsed: elapsed,
            byteCount: byteCount,
            availableBytes: availableBytes
        ) {
            stop(interrupted: false, limit: reason)
        }
    }

    /// How full the session is against whichever limit it will reach first, 0 to 1 (Q-4).
    var limitFraction: Double {
        guard isRecording else { return 0 }
        return limit.fraction(elapsed: elapsed, byteCount: byteCount, availableBytes: availableBytes)
    }

    private func writeCheckpoint() {
        guard let startedAt, let identifier = sessionIdentifier else { return }
        store.writeCheckpoint(
            RecordingCheckpoint(
                identifier: identifier,
                startedAt: startedAt,
                duration: Date.now.timeIntervalSince(startedAt),
                rate: rate,
                tracks: writers.map { $0.snapshot() }.filter { $0.sampleCount > 0 }
            )
        )
    }

    // MARK: - Saved sessions

    /// Whether a name can be given to a recording: anything but blank. The rename field asks
    /// this to keep its button disabled, rather than accepting a blank name and ignoring it.
    static func isValidName(_ name: String) -> Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func rename(_ session: RecordingSession, to name: String) {
        guard Self.isValidName(name) else { return }
        session.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try? context.save()
    }

    func delete(_ session: RecordingSession) {
        let identifier = session.identifier
        context.delete(session)
        try? context.save()
        store.deleteFolder(for: identifier)
    }

    /// The CSV files of one session, for the share sheet (R-44).
    func fileURLs(for session: RecordingSession) -> [URL] {
        store.fileURLs(for: session)
    }

    /// Brings the files on disk and the sessions in the store back into agreement, once, at
    /// launch: a recording the app was killed in the middle of is adopted from its checkpoint,
    /// and only then is anything left over deleted.
    ///
    /// It does nothing at all unless the store opened for real. An in-memory fallback knows
    /// about no sessions, so treating its answer as the truth would delete every recording
    /// the user has.
    func reconcileFiles() {
        guard isStorePersistent, !isRecording else { return }
        let descriptor = FetchDescriptor<RecordingSession>()
        guard let sessions = try? context.fetch(descriptor) else { return }
        var known = Set(sessions.map(\.identifier))

        for checkpoint in store.checkpoints() where !known.contains(checkpoint.identifier) {
            guard !checkpoint.tracks.isEmpty else {
                store.deleteFolder(for: checkpoint.identifier)
                continue
            }
            let session = RecordingSession(
                identifier: checkpoint.identifier,
                name: checkpoint.recoveredName,
                startedAt: checkpoint.startedAt,
                duration: checkpoint.duration,
                rate: checkpoint.rate,
                isInterrupted: true,
                tracks: checkpoint.tracks
            )
            context.insert(session)
            known.insert(checkpoint.identifier)
        }
        // A checkpoint is the only thing a recovered session can be rebuilt from, and an
        // unknown folder is deleted below as an orphan. If saving failed, both are left alone
        // for the next launch to try again, rather than losing the recording outright.
        do {
            try context.save()
        } catch {
            return
        }
        for identifier in known {
            store.removeCheckpoint(for: identifier)
        }
        store.removeFolders(notIn: known)
    }
}

/// Something that went wrong with a recording, and how badly (R-40).
struct RecordingFailure: Equatable {
    enum Kind: Int, Comparable {
        case nothingRecorded
        case samplesDropped
        case stoppedAtLimit
        case couldNotStart
        case discarded

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The alert's title says what happened, so the message underneath can explain it.
        var title: String {
            switch self {
            case .nothingRecorded: "Nothing was recorded"
            case .samplesDropped: "Some samples are missing"
            case .stoppedAtLimit: "Recording saved"
            case .couldNotStart: "Couldn't start recording"
            case .discarded: "Recording not saved"
            }
        }
    }

    let kind: Kind
    let message: String
}

/// A recording that has just been saved, for the confirmation shown as it ends.
struct SavedRecording: Equatable, Identifiable {
    let identifier: UUID
    let name: String

    var id: UUID { identifier }
}
