import SwiftData
import SwiftUI

/// The Recordings tab: saved sessions newest first, and the way into a new one
/// (R-37, R-42).
struct RecordingsView: View {
    @Environment(RecordingService.self) private var recorder
    @Query(sort: \RecordingSession.startedAt, order: .reverse) private var sessions: [RecordingSession]
    @State private var isShowingNewRecording = false

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    EmptyRecordings { isShowingNewRecording = true }
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Recordings")
            .navigationDestination(for: RecordingSession.self) { session in
                RecordingSessionView(session: session)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Recording", systemImage: "plus") {
                        isShowingNewRecording = true
                    }
                    .disabled(recorder.isRecording)
                }
            }
            .sheet(isPresented: $isShowingNewRecording) {
                NewRecordingSheet()
            }
        }
    }

    private func delete(_ offsets: IndexSet) {
        for index in offsets {
            recorder.delete(sessions[index])
        }
    }
}

private struct SessionRow: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(session.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
            HStack(spacing: 6) {
                Text(session.listSummary)
                if session.isInterrupted {
                    Text("Interrupted")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// Shown until the first session exists, so the tab explains itself rather than sitting empty.
private struct EmptyRecordings: View {
    let onStart: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 40)

                Text("No recordings yet")
                    .font(.title3.weight(.semibold))

                Text("Log the readings you choose while Readout is open, keep each session on this iPhone, and export it as CSV through the share sheet.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button("New Recording", systemImage: "record.circle") {
                    onStart()
                }
                .buttonStyle(.glassProminent)
                .padding(.top, 4)

                VStack(alignment: .leading, spacing: 10) {
                    row("slider.horizontal.3", "Pick readings and a sample rate: 1 Hz, 10 Hz or 50 Hz")
                    row("clock", "A recording bar with elapsed time and sample count")
                    row("tablecells", "One CSV per reading, with ISO 8601 timestamps")
                    row("square.and.arrow.up", "Share to Files, AirDrop or Mail")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
                .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
