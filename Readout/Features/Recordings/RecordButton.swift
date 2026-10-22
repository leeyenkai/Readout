import SwiftUI

/// The Record button every reading detail view and every tool carries, which opens the New
/// Recording sheet with this reading already ticked (R-29, R-36, R-37).
///
/// While a recording runs it becomes the way into it: a filled, pulsing record symbol that
/// opens the running recording. It used to sit there disabled, with nothing to say why.
struct RecordButton: View {
    /// The readings to pre-select. One for a detail view, one per tool.
    let readings: [ReadingID]

    @Environment(RecordingService.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themeAccent) private var accent
    @State private var isShowingNewRecording = false
    @State private var isShowingRecording = false

    var body: some View {
        Button {
            if recorder.isRecording {
                isShowingRecording = true
            } else {
                isShowingNewRecording = true
            }
        } label: {
            Label(
                recorder.isRecording ? "Recording" : "Record",
                systemImage: recorder.isRecording ? "record.circle.fill" : "record.circle"
            )
            .foregroundStyle(recorder.isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint))
            .symbolEffect(.pulse, isActive: recorder.isRecording && !reduceMotion)
            .contentTransition(.symbolEffect(.replace))
        }
        // A toolbar draws its buttons in the tint, whatever the label asks for. The theme's
        // accent is passed back explicitly: a nil tint resets it to the system's own.
        .tint(recorder.isRecording ? .red : accent)
        .sheet(isPresented: $isShowingNewRecording) {
            NewRecordingSheet(preselected: readings)
        }
        .sheet(isPresented: $isShowingRecording) {
            LiveRecordingView()
        }
        .accessibilityHint(recorder.isRecording ? "Opens the running recording" : "Starts a recording with this reading chosen")
    }
}
