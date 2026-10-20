import SwiftData
import SwiftUI

@main
struct ReadoutApp: App {
    @State private var settings: AppSettings
    @State private var hub: SensorHub
    @State private var recorder: RecordingService

    private let container: ModelContainer

    init() {
        let settings = AppSettings()
        let hub = SensorHub(settings: settings)
        let store = Self.makeContainer()
        _settings = State(initialValue: settings)
        _hub = State(initialValue: hub)
        _recorder = State(initialValue: RecordingService(
            hub: hub,
            store: RecordingStore(),
            context: store.container.mainContext,
            settings: settings,
            isStorePersistent: store.isPersistent
        ))
        self.container = store.container
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(hub)
                .environment(recorder)
        }
        .modelContainer(container)
    }

    /// Session metadata is kept in SwiftData (R-61). If the store cannot be opened the app
    /// still runs on an in-memory one: readings and tools do not depend on it, and saying so
    /// is better than refusing to launch.
    ///
    /// The caller is told which it got. An in-memory store knows about no sessions, and code
    /// that takes that for the truth — the launch-time tidy-up of files no session points at
    /// — would delete every recording on the device.
    private static func makeContainer() -> (container: ModelContainer, isPersistent: Bool) {
        let schema = Schema([RecordingSession.self])
        // A newly installed app has no Application Support directory and SwiftData will not
        // make one, so the store is given an explicit URL in a directory created here —
        // beside the CSV files, which live in the same place (R-57, R-61).
        if let support = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            let configuration = ModelConfiguration(
                schema: schema,
                url: support.appending(path: "Recordings.store")
            )
            if let container = try? ModelContainer(for: schema, configurations: configuration) {
                return (container, true)
            }
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        guard let container = try? ModelContainer(for: schema, configurations: memory) else {
            preconditionFailure("SwiftData could not open a store for RecordingSession")
        }
        return (container, false)
    }
}
