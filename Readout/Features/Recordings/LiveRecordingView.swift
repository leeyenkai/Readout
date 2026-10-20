import SwiftUI

/// What a running session is logging, while it logs it (R-79).
///
/// The recording bar says a session exists; this says what is in it. Start a recording at the
/// top of a journey and this is the screen to leave open: every chosen reading live, the
/// route building up as the fixes arrive, and how much of the session's limit is left.
///
/// It takes no leases of its own. The recording already holds one per reading it is logging,
/// so everything here is the same stream being written to the CSV — nothing is started or
/// kept running just because this screen is open (R-64).
struct LiveRecordingView: View {
    @Environment(RecordingService.self) private var recorder
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summary

                    if !recorder.route.isEmpty {
                        RoutePanel(route: recorder.route)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(recorder.readings, id: \.self) { reading in
                            let descriptor = ReadingCatalog.descriptor(reading)
                            ReadingTile(
                                descriptor: descriptor,
                                availability: hub.availability(reading),
                                sample: hub.sample(reading),
                                trail: hub.trail(reading),
                                units: settings.displayUnits
                            )
                        }
                    }

                    foregroundNote

                    Button("Stop recording", systemImage: "stop.circle") {
                        recorder.stop()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Nothing left to watch once the session has been saved, and the summary below
            // would start counting from zero.
            .onChange(of: recorder.isRecording) { _, isRecording in
                if !isRecording { dismiss() }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 10) {
            Text(RecordingNaming.elapsedText(recorder.elapsed))
                .readoutValue(size: 52)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("\(RecordingNaming.sampleCountText(recorder.sampleCount)) · \(recorder.byteCount.formatted(.byteCount(style: .file))) · \(recorder.rate.summary)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            ProgressView(value: recorder.limitFraction)
                .tint(recorder.limitFraction >= 0.8 ? .orange : nil)
                .accessibilityLabel("Session limit")
                .accessibilityValue("\(Int(recorder.limitFraction * 100)) per cent used")

            Text(limitNote)
                .font(.caption2)
                .foregroundStyle(recorder.limitFraction >= 0.8 ? .orange : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording for \(RecordingNaming.elapsedText(recorder.elapsed)), \(RecordingNaming.sampleCountText(recorder.sampleCount))")
    }

    private var limitNote: String {
        recorder.limitFraction >= 0.8
            ? "Nearing this session's limit — it will stop and save itself."
            : "Stops by itself at this session's limit: \(recorder.limit.title.lowercased())."
    }

    /// What happens if the phone goes in a pocket — which is exactly what somebody logging a
    /// journey is about to do (R-41, R-82).
    private var foregroundNote: some View {
        let verdict = recorder.backgroundVerdict

        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(verdict.shortSummary)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(verdict.continuesInBackground
                        ? AnyShapeStyle(.tint)
                        : AnyShapeStyle(.secondary))
                Text(verdict.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Control Centre, the app switcher and a call banner are all fine either way.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        } icon: {
            Image(systemName: verdict.symbol)
                .foregroundStyle(verdict.continuesInBackground
                    ? AnyShapeStyle(.tint)
                    : AnyShapeStyle(.secondary))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }
}
