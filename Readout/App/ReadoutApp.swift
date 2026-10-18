import SwiftUI

@main
struct ReadoutApp: App {
    @State private var settings: AppSettings
    @State private var hub: SensorHub

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _hub = State(initialValue: SensorHub(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(hub)
        }
    }
}
