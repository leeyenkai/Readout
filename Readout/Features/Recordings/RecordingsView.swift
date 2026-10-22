import SwiftData
import SwiftUI

/// The Recordings tab: saved recordings newest first, and the way into a new one
/// (R-37, R-42).
struct RecordingsView: View {
    @Environment(RecordingService.self) private var recorder
    @Query(sort: \RecordingSession.startedAt, order: .reverse, animation: .readoutSnappy)
    private var sessions: [RecordingSession]
    @State private var path: [RecordingSession] = []
    @State private var isShowingNewRecording = false
    @State private var isShowingRecording = false
    @State private var pendingDeletion: RecordingSession?
    /// Deleted from its own screen, and waiting for that screen to finish leaving.
    @State private var deletingOnceGone: RecordingSession?
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if !recorder.isStorePersistent {
                    StoreUnavailableNotice()
                } else if sessions.isEmpty {
                    EmptyRecordings(
                        isRecording: recorder.isRecording,
                        onStart: { isShowingNewRecording = true },
                        onOpen: { isShowingRecording = true }
                    )
                    .transition(.blurReplace)
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) {
                                SessionRow(session: session)
                            }
                            .matchedTransitionSource(id: session.identifier, in: zoom)
                            // Swiping asks first, as Delete on the recording's own screen
                            // does: either way the CSV files go for good.
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    pendingDeletion = session
                                }
                            }
                        }
                        .themedRows()
                    }
                    .transition(.opacity)
                }
            }
            .motion(.readoutSmooth, value: sessions.isEmpty)
            .navigationTitle("Recordings")
            .navigationDestination(for: RecordingSession.self) { session in
                RecordingSessionView(session: session) {
                    deletingOnceGone = session
                    path.removeAll { $0.identifier == session.identifier }
                }
                .navigationTransition(.zoom(sourceID: session.identifier, in: zoom))
                // Deleted once the screen has gone, not while it is leaving: deleting it from
                // underneath its own view let the view redraw during the pop with an object
                // SwiftData had already thrown away.
                .onDisappear {
                    guard deletingOnceGone?.identifier == session.identifier else { return }
                    deletingOnceGone = nil
                    withReadoutAnimation { recorder.delete(session) }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    // The same Record button as every reading and tool: a new recording, or —
                    // while one runs — the way into it.
                    RecordButton(readings: [])
                        .disabled(!recorder.isStorePersistent)
                }
            }
            .sheet(isPresented: $isShowingNewRecording) {
                NewRecordingSheet()
            }
            .sheet(isPresented: $isShowingRecording) {
                LiveRecordingView()
            }
            .confirmationDialog(
                "Delete this recording?",
                isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                titleVisibility: .visible,
                presenting: pendingDeletion
            ) { session in
                Button("Delete", role: .destructive) {
                    withReadoutAnimation { recorder.delete(session) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Its CSV files are removed from this iPhone. Anything you have already exported is kept.")
            }
            .themedSurface()
        }
    }
}

/// Shown when SwiftData could not open its store. Saying so is the honest answer: the
/// recordings are still on the device, and nothing has been deleted (P-2).
private struct StoreUnavailableNotice: View {
    var body: some View {
        ContentUnavailableView {
            Label("Recordings unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("""
                Readout could not open the file that lists your recordings, so it cannot show \
                them or make a new one. Nothing has been deleted — the recordings are still on \
                this iPhone. Restarting Readout usually clears this.
                """)
        }
    }
}

private struct SessionRow: View {
    let session: RecordingSession

    var body: some View {
        HStack(spacing: 12) {
            ReadingSymbols(readings: session.tracks.map(\.reading))
            VStack(alignment: .leading, spacing: 3) {
                Text(session.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.listSummary)
                    if session.isInterrupted {
                        Label("Interrupted", systemImage: "exclamationmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The symbols of a recording's first few readings, so the list can be scanned by eye.
private struct ReadingSymbols: View {
    let readings: [ReadingID]

    var body: some View {
        let shown = Array(readings.prefix(4))
        ZStack {
            Circle()
                .fill(.tint.opacity(0.14))
            if shown.count == 1, let reading = shown.first {
                Image(systemName: ReadingCatalog.descriptor(reading).symbol)
                    .font(.subheadline.weight(.semibold))
            } else {
                Grid(horizontalSpacing: 2, verticalSpacing: 2) {
                    GridRow {
                        symbol(at: 0, in: shown)
                        symbol(at: 1, in: shown)
                    }
                    GridRow {
                        symbol(at: 2, in: shown)
                        symbol(at: 3, in: shown)
                    }
                }
                .font(.system(size: 10, weight: .semibold))
            }
        }
        .foregroundStyle(.tint)
        .frame(width: 40, height: 40)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func symbol(at index: Int, in readings: [ReadingID]) -> some View {
        if readings.indices.contains(index) {
            Image(systemName: ReadingCatalog.descriptor(readings[index]).symbol)
                .frame(width: 14, height: 14)
        } else {
            Color.clear.frame(width: 14, height: 14)
        }
    }
}

/// Shown until the first recording exists, so the tab explains itself rather than sitting
/// empty — or, during the very first recording, says that one is running.
private struct EmptyRecordings: View {
    let isRecording: Bool
    let onStart: () -> Void
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: isRecording ? "record.circle.fill" : "record.circle")
                    .font(.system(size: 52))
                    .foregroundStyle(isRecording ? AnyShapeStyle(Color.red) : AnyShapeStyle(.tint))
                    .symbolEffect(.pulse, isActive: isRecording && !reduceMotion)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.top, 40)

                Text(isRecording ? "Your first recording is running" : "No recordings yet")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text(isRecording
                     ? "It appears here as soon as you stop it."
                     : "Log the readings you choose, keep each recording on this iPhone, and export it as CSV through the share sheet.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if isRecording {
                    Button("Open recording", systemImage: "waveform.path.ecg", action: onOpen)
                        .buttonStyle(.glassProminent)
                        .padding(.top, 4)
                } else {
                    Button("New recording", systemImage: "record.circle", action: onStart)
                        .buttonStyle(.glassProminent)
                        .padding(.top, 4)
                }

                VStack(alignment: .leading, spacing: 12) {
                    row("slider.horizontal.3", "Pick readings and a sample rate: 1 Hz, 10 Hz or 50 Hz")
                    row("location.fill", "A recording that logs your position carries on in your pocket")
                    row("map", "See the route a journey took, plotted on the phone")
                    row("tablecells", "One CSV per reading, with ISO 8601 timestamps")
                    row("square.and.arrow.up", "Share to Files, AirDrop or Mail")
                }
                .readoutCard()
                .padding(.top, 8)
            }
            .motion(.readoutSnappy, value: isRecording)
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, Metrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
            Spacer(minLength: 0)
        }
    }
}
