import SwiftUI

/// The three tabs of v1, in the system glass tab bar (R-46), with the recording bar floating
/// above them while a session runs (R-40).
struct RootView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: AppTab = .readings

    var body: some View {
        TabView(selection: $selection) {
            Tab(AppTab.readings.title, systemImage: AppTab.readings.symbol, value: AppTab.readings) {
                ReadingsView().modifier(RecordingBarInset())
            }
            Tab(AppTab.tools.title, systemImage: AppTab.tools.symbol, value: AppTab.tools) {
                ToolsView().modifier(RecordingBarInset())
            }
            Tab(AppTab.recordings.title, systemImage: AppTab.recordings.symbol, value: AppTab.recordings) {
                RecordingsView().modifier(RecordingBarInset())
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Every sensor stops the moment the app is no longer in front (R-64, P-3).
            //
            // A recording is a different matter. `.inactive` is also what a swipe into
            // Control Centre, a half-swipe to the app switcher and an incoming-call banner
            // look like, and ending a field recording for any of those made a long session
            // nearly impossible to finish. Only going to the background stops it (R-41).
            switch phase {
            case .active: hub.resume()
            case .inactive: if !recorder.isRecording { hub.suspend() }
            case .background: leaveForeground()
            @unknown default: leaveForeground()
            }
        }
        .onChange(of: settings.accelerationIncludesGravity) { _, _ in hub.apply(settings) }
        .onChange(of: settings.usesTrueNorth) { _, _ in hub.apply(settings) }
        .onChange(of: settings.soundCalibrationOffset) { _, _ in hub.apply(settings) }
        .onChange(of: settings.soundRespondsFast) { _, _ in hub.apply(settings) }
        .onChange(of: settings.lightCalibration) { _, _ in hub.apply(settings) }
        .sensoryFeedback(trigger: recorder.isRecording) { _, isRecording in
            // A tap as a recording starts and another as it stops (R-51).
            guard settings.hapticsEnabled else { return nil }
            return isRecording ? .start : .stop
        }
        .alert(
            "Recording",
            isPresented: Binding(
                get: { recorder.failure != nil },
                set: { if !$0 { recorder.failure = nil } }
            )
        ) {
            Button("OK") { recorder.failure = nil }
        } message: {
            Text(recorder.failure?.message ?? "")
        }
        .task {
            recorder.reconcileFiles()
        }
        // First run only: what the app measures, what is an estimate, where the data goes
        // — before the first permission prompt arrives (R-73).
        .sheet(isPresented: Binding(
            get: { !settings.hasSeenWelcome },
            set: { if !$0 { settings.hasSeenWelcome = true } }
        )) {
            WelcomeSheet()
        }
    }

    /// Recording is foreground-only in v1: leaving the app stops the session and saves it
    /// with an interrupted note (R-41). A recording keeps its sensors through `.inactive`,
    /// or glancing at Control Centre would leave the session running but recording nothing.
    private func leaveForeground() {
        recorder.stop(interrupted: true)
        hub.suspend()
    }
}

/// Floats the recording bar just above the tab bar, in whichever tab is open, for as long as
/// a recording runs (R-40).
///
/// Each tab gets its own inset rather than the whole `TabView`: an inset on the TabView lands
/// on top of the tab bar, and the system's bottom accessory slot keeps its glass tray even
/// when it has nothing to show.
private struct RecordingBarInset: ViewModifier {
    @Environment(RecordingService.self) private var recorder

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            if recorder.isRecording {
                RecordingBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: recorder.isRecording)
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
