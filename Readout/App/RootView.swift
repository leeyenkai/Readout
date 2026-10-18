import SwiftUI

/// The three tabs of v1, in the system glass tab bar (R-46).
struct RootView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .readings

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.readings.title, systemImage: AppTab.readings.symbol, value: AppTab.readings) {
                ReadingsView()
            }
            Tab(AppTab.tools.title, systemImage: AppTab.tools.symbol, value: AppTab.tools) {
                ToolsView()
            }
            Tab(AppTab.recordings.title, systemImage: AppTab.recordings.symbol, value: AppTab.recordings) {
                RecordingsView()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Every sensor stops the moment the app is no longer in front (R-64, P-3).
            switch phase {
            case .active: hub.resume()
            case .inactive, .background: hub.suspend()
            @unknown default: hub.suspend()
            }
        }
        .onChange(of: settings.accelerationIncludesGravity) { _, _ in hub.apply(settings) }
        .onChange(of: settings.usesTrueNorth) { _, _ in hub.apply(settings) }
        .onChange(of: settings.soundCalibrationOffset) { _, _ in hub.apply(settings) }
        .onChange(of: settings.soundRespondsFast) { _, _ in hub.apply(settings) }
        .onChange(of: settings.lightCalibration) { _, _ in hub.apply(settings) }
    }
}

enum AppTab: Hashable {
    case readings, tools, recordings

    var title: String {
        switch self {
        case .readings: "Readings"
        case .tools: "Tools"
        case .recordings: "Recordings"
        }
    }

    var symbol: String {
        switch self {
        case .readings: "square.grid.2x2"
        case .tools: "ruler"
        case .recordings: "record.circle"
        }
    }
}
