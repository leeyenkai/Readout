import Foundation
import SwiftData
import Testing
@testable import Readout

/// The file side of recording: what survives a crash, and what is safe to delete.
///
/// `removeFolders(notIn:)` is the one call in Readout that can destroy a user's recordings,
/// and it had no coverage. It used to be reachable with an empty set of known sessions —
/// which deletes everything — whenever SwiftData fell back to an in-memory store.
@MainActor
@Suite("Recording files and recovery")
struct RecordingRecoveryTests {
    private func makeStore() -> RecordingStore {
        RecordingStore(root: throwawayDirectory().appending(path: "Recordings", directoryHint: .isDirectory))
    }

    private func makeService(
        store: RecordingStore,
        isStorePersistent: Bool = true
    ) throws -> (service: RecordingService, container: ModelContainer) {
        // The schema has to be on the configuration as well as the container, or the fetch
        // below finds no configuration for the model and traps inside SwiftData.
        let schema = Schema([RecordingSession.self])
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        let settings = AppSettings(defaults: throwawayDefaults())
        let service = RecordingService(
            hub: SensorHub(settings: settings),
            store: store,
            context: container.mainContext,
            settings: settings,
            isStorePersistent: isStorePersistent
        )
        // The container is handed back so the test keeps it alive: let it go out of scope and
        // the context it owns goes with it, and the next use traps inside SwiftData.
        return (service, container)
    }

    private func savedSessions(_ container: ModelContainer) throws -> [RecordingSession] {
        try container.mainContext.fetch(FetchDescriptor<RecordingSession>())
    }

    private func sampleTrack() -> RecordedTrack {
        RecordedTrack(
            reading: .acceleration,
            fileName: "accel.csv",
            sampleCount: 12,
            byteCount: 480,
            channels: [RecordedChannelSummary(minimum: -1, maximum: 1, mean: 0, count: 12)]
        )
    }

    // MARK: - The delete primitive

    @Test("A folder no session points at is removed")
    func orphanIsRemoved() throws {
        let store = makeStore()
        let orphan = UUID()
        try store.createFolder(for: orphan)

        store.removeFolders(notIn: [])

        #expect(!FileManager.default.fileExists(atPath: store.folder(for: orphan).path(percentEncoded: false)))
    }

    @Test("A folder still carrying a checkpoint is never removed as an orphan")
    func checkpointedFolderSurvives() throws {
        let store = makeStore()
        let identifier = UUID()
        try store.createFolder(for: identifier)
        store.writeCheckpoint(
            RecordingCheckpoint(
                identifier: identifier,
                startedAt: .now,
                duration: 6,
                rate: .medium,
                tracks: [sampleTrack()]
            )
        )

        store.removeFolders(notIn: [])

        #expect(FileManager.default.fileExists(atPath: store.folder(for: identifier).path(percentEncoded: false)))
    }

    @Test("A checkpoint round-trips")
    func checkpointRoundTrip() throws {
        let store = makeStore()
        let identifier = UUID()
        try store.createFolder(for: identifier)
        let written = RecordingCheckpoint(
            identifier: identifier,
            startedAt: Date(timeIntervalSince1970: 1_000),
            duration: 42,
            rate: .high,
            tracks: [sampleTrack()]
        )
        store.writeCheckpoint(written)

        let read = try #require(store.checkpoints().first)
        #expect(read == written)

        store.removeCheckpoint(for: identifier)
        #expect(store.checkpoints().isEmpty)
    }

    // MARK: - Reconciling at launch

    @Test("A recording the app was killed during is recovered, not deleted")
    func interruptedRecordingIsAdopted() throws {
        let store = makeStore()
        let (service, container) = try makeService(store: store)
        let identifier = UUID()
        try store.createFolder(for: identifier)
        store.writeCheckpoint(
            RecordingCheckpoint(
                identifier: identifier,
                startedAt: .now.addingTimeInterval(-30),
                duration: 30,
                rate: .medium,
                tracks: [sampleTrack()]
            )
        )

        service.reconcileFiles()

        #expect(
            FileManager.default.fileExists(atPath: store.folder(for: identifier).path(percentEncoded: false)),
            "the samples are still on disk"
        )
        let sessions = try savedSessions(container)
        #expect(sessions.count == 1)
        #expect(sessions.first?.identifier == identifier)
        #expect(sessions.first?.isInterrupted == true)
        #expect(store.checkpoints().isEmpty, "the checkpoint is cleared once the session exists")
    }

    @Test("A checkpoint with no samples in it is cleaned up rather than recovered")
    func emptyCheckpointIsDropped() throws {
        let store = makeStore()
        let (service, container) = try makeService(store: store)
        let identifier = UUID()
        try store.createFolder(for: identifier)
        store.writeCheckpoint(
            RecordingCheckpoint(identifier: identifier, startedAt: .now, duration: 0, rate: .low, tracks: [])
        )

        service.reconcileFiles()

        #expect(!FileManager.default.fileExists(atPath: store.folder(for: identifier).path(percentEncoded: false)))
        #expect(try savedSessions(container).isEmpty)
    }

    @Test("Nothing is deleted when the session store could not be opened")
    func fallbackStoreDeletesNothing() throws {
        let store = makeStore()
        let (service, _) = try makeService(store: store, isStorePersistent: false)
        let existing = UUID()
        try store.createFolder(for: existing)

        service.reconcileFiles()

        #expect(
            FileManager.default.fileExists(atPath: store.folder(for: existing).path(percentEncoded: false)),
            "an in-memory store knows about no sessions, so everything on disk would look orphaned"
        )
    }

    @Test("A recording cannot be started while the session store is unavailable")
    func cannotRecordWithoutAStore() throws {
        let store = makeStore()
        let (service, _) = try makeService(store: store, isStorePersistent: false)

        service.start(readings: [.acceleration], rate: .medium)

        #expect(!service.isRecording)
        #expect(service.failure?.kind == .couldNotStart)
    }

    // MARK: - Failure precedence

    @Test("The most serious failure is the one reported")
    func failureOrdering() {
        #expect(RecordingFailure.Kind.discarded > RecordingFailure.Kind.couldNotStart)
        #expect(RecordingFailure.Kind.couldNotStart > RecordingFailure.Kind.stoppedAtLimit)
        #expect(RecordingFailure.Kind.stoppedAtLimit > RecordingFailure.Kind.samplesDropped)
    }
}
