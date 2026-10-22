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
        // The chosen look and interface size, applied once for every tab and every screen
        // they push (R-77, R-78). Sheets are their own presentations and dress themselves.
        .themed()
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
            recorder.failure?.kind.title ?? "Recording",
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

    /// Leaving the app ends a recording — unless the session is one that may carry on (R-82).
    ///
    /// A qualifying session keeps the readings it is logging: Core Location holds the app
    /// alive, and the other providers go on delivering because the process is never
    /// suspended. Everything else stops, including whatever the screen behind it was showing —
    /// the microphone and the camera above all, which never run unattended (R-83). A session
    /// that does not qualify stops and saves with an interrupted note, exactly as every
    /// session did before (R-41).
    ///
    /// A recording also keeps its sensors through `.inactive`, or glancing at Control Centre
    /// would leave the session running but recording nothing.
    private func leaveForeground() {
        if recorder.continuesInBackground {
            hub.suspend(keeping: Set(recorder.readings))
        } else {
            recorder.stop(interrupted: true)
            hub.suspend()
        }
    }
}

/// Floats the recording bar just above the tab bar, in whichever tab is open, for as long as
/// a recording runs (R-40) — and, as it ends, the confirmation that it was saved.
///
/// Each tab gets its own inset rather than the whole `TabView`: an inset on the TabView lands
/// on top of the tab bar, and the system's bottom accessory slot keeps its glass tray even
/// when it has nothing to show.
private struct RecordingBarInset: ViewModifier {
    @Environment(RecordingService.self) private var recorder
    @State private var saved: SavedRecording?

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            ZStack {
                if recorder.isRecording {
                    RecordingBar()
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let saved {
                    SavedToast(recording: saved)
                        .transition(.blurReplace.combined(with: .scale(0.92, anchor: .bottom)))
                }
            }
        }
        .motion(.readoutSpring, value: recorder.isRecording)
        .motion(.readoutSpring, value: saved)
        .onChange(of: recorder.lastSaved) { _, recording in
            guard let recording else { return }
            saved = recording
            Task {
                try? await Task.sleep(for: .seconds(2.6))
                if saved == recording { saved = nil }
            }
        }
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
