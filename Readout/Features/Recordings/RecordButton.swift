import SwiftUI

/// The Record button every reading detail view and every tool carries, which opens the New
/// Recording sheet with this reading already ticked (R-29, R-36, R-37).
struct RecordButton: View {
    /// The readings to pre-select. One for a detail view, one per tool.
    let readings: [ReadingID]

    @Environment(RecordingService.self) private var recorder
    @State private var isShowingSheet = false

    var body: some View {
        Button("Record", systemImage: "record.circle") {
            isShowingSheet = true
        }
        .disabled(recorder.isRecording)
        .sheet(isPresented: $isShowingSheet) {
            NewRecordingSheet(preselected: readings)
        }
        .accessibilityHint("Starts a recording with this reading chosen")
    }
}
