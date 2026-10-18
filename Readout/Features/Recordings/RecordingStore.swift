import Foundation

/// Where recordings live: one folder per session under Application Support, one CSV per
/// reading inside it (R-57, R-61).
///
/// Application Support rather than Documents, because these files are the app's own until the
/// user exports them through the share sheet.
struct RecordingStore {
    let root: URL

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL.temporaryDirectory
        root = support.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    func folder(for identifier: UUID) -> URL {
        root.appending(path: identifier.uuidString, directoryHint: .isDirectory)
    }

    @discardableResult
    func createFolder(for identifier: UUID) throws -> URL {
        let folder = folder(for: identifier)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
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

    /// Removes sample folders no session points at any more — a save that failed, or a
    /// delete that was interrupted — so the disk never keeps what the list cannot show.
    func removeFolders(notIn identifiers: Set<UUID>) {
        guard let folders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for folder in folders {
            guard let identifier = UUID(uuidString: folder.lastPathComponent) else { continue }
            guard !identifiers.contains(identifier) else { continue }
            try? fileManager.removeItem(at: folder)
        }
    }
}
