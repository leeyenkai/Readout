import Foundation
@testable import Readout

/// A `UserDefaults` of its own per test, so nothing a test writes reaches the test host's
/// real preferences or the next test.
func throwawayDefaults() -> UserDefaults {
    let name = "readout.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// A fresh temporary directory, removed when the test process exits.
func throwawayDirectory() -> URL {
    let url = URL.temporaryDirectory.appending(path: "readout-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
