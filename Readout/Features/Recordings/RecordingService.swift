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

    /// Set when a recording could not start, or a session could not be saved, for an alert.
    var failure: String?

    let store: RecordingStore

    private let hub: SensorHub
    private let context: ModelContext
    private var writers: [RecordingTrackWriter] = []
    private var sessionIdentifier: UUID?
    private var timer: Timer?

    /// How often the bar's numbers are refreshed and the row buffers are flushed.
    private static let tickInterval: TimeInterval = 0.5

    init(hub: SensorHub, store: RecordingStore, context: ModelContext) {
        self.hub = hub
        self.store = store
        self.context = context
        hub.sampleObserver = { [weak self] reading, sample in
            self?.receive(reading, sample)
        }
    }

    var isRecording: Bool { startedAt != nil }

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
            failure = "Readout could not make room for this recording on the device."
            return
        }

        sessionIdentifier = identifier
        startedAt = start
        self.rate = rate
        self.readings = ordered
        sampleCount = 0
        elapsed = 0
        for reading in ordered {
            hub.activate(reading, rate: rate.activationRate)
        }
        // The screen stays awake for as long as the recording runs (R-40).
        UIApplication.shared.isIdleTimerDisabled = true
        startTicking()
    }

    /// Stops the recording and saves it. `interrupted` marks a session the app left the
    /// foreground in the middle of (R-41).
    func stop(interrupted: Bool = false) {
        guard let startedAt, let identifier = sessionIdentifier else { return }
        timer?.invalidate()
        timer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        for reading in readings {
            hub.deactivate(reading, rate: rate.activationRate)
        }

        let tracks = writers.map { $0.finish() }
        let failedToWrite = writers.contains { $0.hasFailed }
        let duration = Date.now.timeIntervalSince(startedAt)
        let recorded = tracks.filter { $0.sampleCount > 0 }
        writers = []

        if recorded.isEmpty {
            // Nothing arrived — a recording stopped within a moment of starting, or every
            // reading stayed silent. An empty session is clutter, so it is dropped.
            store.deleteFolder(for: identifier)
        } else {
            save(
                identifier: identifier,
                startedAt: startedAt,
                duration: duration,
                tracks: recorded,
                isInterrupted: interrupted
            )
        }
        if failedToWrite {
            failure = "Some samples could not be written to the device, so this recording may be short."
        }

        self.startedAt = nil
        sessionIdentifier = nil
        readings = []
        elapsed = 0
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
        } catch {
            context.delete(session)
            store.deleteFolder(for: identifier)
            failure = "This recording could not be saved, so it has been discarded."
        }
    }

    private func receive(_ reading: ReadingID, _ sample: SensorSample) {
        guard isRecording else { return }
        guard let writer = writers.first(where: { $0.reading == reading }) else { return }
        writer.receive(sample)
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
        sampleCount = writers.reduce(0) { $0 + $1.sampleCount }
        for writer in writers {
            writer.flush()
        }
    }

    // MARK: - Saved sessions

    func rename(_ session: RecordingSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        session.name = trimmed
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

    /// Drops sample folders that no longer belong to a session, in case a delete or a save
    /// was cut short.
    func removeOrphanedFiles() {
        let descriptor = FetchDescriptor<RecordingSession>()
        guard let sessions = try? context.fetch(descriptor) else { return }
        store.removeFolders(notIn: Set(sessions.map(\.identifier)))
    }
}
