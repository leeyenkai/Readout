import Foundation

/// Where recordings live: one folder per session under Application Support, one CSV per
/// reading inside it (R-57, R-61).
///
/// Application Support rather than Documents, because these files are the app's own until the
/// user exports them through the share sheet.
struct RecordingStore {
    let root: URL

    private let fileManager: FileManager

    /// `root` is only passed by tests, which point the store at a temporary directory
    /// rather than the test host's own Application Support.
    init(fileManager: FileManager = .default, root: URL? = nil) {
        self.fileManager = fileManager
        if let root {
            self.root = root
            return
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        self.root = support.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    func folder(for identifier: UUID) -> URL {
        root.appending(path: identifier.uuidString, directoryHint: .isDirectory)
    }

    @discardableResult
    func createFolder(for identifier: UUID) throws -> URL {
        let folder = folder(for: identifier)
        // Declared rather than left to the default: a recording is the user's own data, and
        // it should be no more readable than the device's first unlock (R-57). Full
        // protection is deliberately not used — it would fail the writes if the screen
        // locked during a session.
        try fileManager.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        return folder
    }

    func deleteFolder(for identifier: UUID) {
        try? fileManager.removeItem(at: folder(for: identifier))
    }

    /// The files the share sheet sends, in the session's own reading order (R-44).
    func fileURLs(for session: RecordingSession) -> [URL] {
        let folder = folder(for: session.identifier)
        return session.tracks
            .map { folder.appending(path: $0.fileName) }
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
    }

    func fileURL(for track: RecordedTrack, in session: RecordingSession) -> URL {
        folder(for: session.identifier).appending(path: track.fileName)
    }

    func byteCount(at url: URL) -> Int {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    }

    /// Space the system is willing to give an important write, in bytes. Nil when the volume
    /// will not say, in which case the caller carries on rather than refusing to record.
    func availableBytes() -> Int64? {
        try? root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    // MARK: - Checkpoints

    /// Saves the running session's metadata beside its CSV files, so a recording the app is
    /// killed in the middle of can be recovered on the next launch.
    func writeCheckpoint(_ checkpoint: RecordingCheckpoint) {
        guard let data = try? JSONEncoder().encode(checkpoint) else { return }
        try? data.write(to: checkpointURL(for: checkpoint.identifier), options: .atomic)
    }

    func removeCheckpoint(for identifier: UUID) {
        try? fileManager.removeItem(at: checkpointURL(for: identifier))
    }

    /// Every checkpoint still on disk, newest first. One being here means its recording never
    /// reached `stop()`.
    func checkpoints() -> [RecordingCheckpoint] {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return folders
            .compactMap { folder -> RecordingCheckpoint? in
                guard UUID(uuidString: folder.lastPathComponent) != nil else { return nil }
                guard let data = try? Data(contentsOf: folder.appending(path: Self.checkpointName)) else { return nil }
                return try? JSONDecoder().decode(RecordingCheckpoint.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private func checkpointURL(for identifier: UUID) -> URL {
        folder(for: identifier).appending(path: Self.checkpointName)
    }

    private static let checkpointName = "session.json"

    /// Removes sample folders no session points at any more — a save that failed, or a
    /// delete that was interrupted — so the disk never keeps what the list cannot show.
    ///
    /// This is the one call in Readout that can destroy a user's recordings, so it is only
    /// ever reached from `RecordingService.reconcileFiles()`, which first checks that the
    /// session store opened for real and that nothing is recording. A folder still carrying a
    /// checkpoint is left alone whatever the caller passes: it is an unsaved recording, not
    /// an orphan.
    func removeFolders(notIn identifiers: Set<UUID>) {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for folder in folders {
            guard let identifier = UUID(uuidString: folder.lastPathComponent) else { continue }
            guard !identifiers.contains(identifier) else { continue }
            let checkpoint = folder.appending(path: Self.checkpointName)
            guard !fileManager.fileExists(atPath: checkpoint.path(percentEncoded: false)) else { continue }
            try? fileManager.removeItem(at: folder)
        }
    }
}
