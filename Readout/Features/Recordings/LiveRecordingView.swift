import SwiftUI

/// What a running recording is logging, while it logs it (R-79).
///
/// The recording bar says a recording exists; this says what is in it. Start one at the top of
/// a journey and this is the screen to leave open: every chosen reading live, the route
/// building up as positions arrive, and how much of the recording's limit is left.
///
/// It takes no leases of its own. The recording already holds one per reading it is logging,
/// so everything here is the same stream being written to the CSV — nothing is started or
/// kept running just because this screen is open (R-64).
struct LiveRecordingView: View {
    @Environment(RecordingService.self) private var recorder
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themeAccent) private var accent

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Metrics.stackSpacing) {
                    summary

                    if !recorder.route.isEmpty {
                        RoutePanel(route: recorder.route)
                            .transition(.blurReplace)
                    }

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(recorder.readings, id: \.self) { reading in
                            // Each tile follows its own reading, so the grid is not redrawn
                            // for every sample of every reading being logged (R-65).
                            LiveReadingTile(
                                descriptor: ReadingCatalog.descriptor(reading),
                                units: settings.displayUnits
                            )
                        }
                    }

                    foregroundNote
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, Metrics.bottomPadding)
            }
            .scrollIndicators(.hidden)
            // Always in reach, however many readings are being logged above it: it used to sit
            // at the end of the scroll, below the fold.
            .safeAreaInset(edge: .bottom) {
                Button(role: .destructive) {
                    recorder.stop()
                } label: {
                    Label("Stop recording", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.red)
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, 8)
            }
            .navigationTitle("Recording")
            .navigationBarTitleDisplayMode(.inline)
            .themedSurface()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .motion(.readoutSmooth, value: recorder.route.isEmpty)
            // Nothing left to watch once the recording has been saved, and the summary below
            // would start counting from zero.
            .onChange(of: recorder.isRecording) { _, isRecording in
                if !isRecording { dismiss() }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle.fill")
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                Text("Recording")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(RecordingNaming.elapsedText(recorder.elapsed))
                .readoutValue(size: 56)
                .monospacedDigit()
                .contentTransition(.numericText())
                .motion(.readoutSnappy, value: recorder.elapsed)

            Text("\(RecordingNaming.sampleCountText(recorder.sampleCount)) · \(recorder.byteCount.formatted(.byteCount(style: .file))) · \(recorder.rate.summary)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .contentTransition(.numericText())

            ProgressView(value: recorder.limitFraction)
                .tint(recorder.limitFraction >= 0.8 ? Color.orange : accent)
                .motion(.readoutSmooth, value: recorder.limitFraction)
                .accessibilityLabel("Recording limit")
                .accessibilityValue("\(Int(recorder.limitFraction * 100)) per cent used")

            Text(limitNote)
                .font(.caption)
                .foregroundStyle(recorder.limitFraction >= 0.8 ? .orange : .secondary)
                .multilineTextAlignment(.center)
        }
        .readoutCard(padding: 20, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording for \(RecordingNaming.elapsedText(recorder.elapsed)), \(RecordingNaming.sampleCountText(recorder.sampleCount))")
    }

    private var limitNote: String {
        recorder.limitFraction >= 0.8
            ? "Nearing this recording's limit — it will stop and save itself."
            : "Stops by itself at this recording's limit: \(recorder.limit.title.lowercased())."
    }

    /// What happens if the phone goes in a pocket — which is exactly what somebody logging a
    /// journey is about to do (R-41, R-82).
    private var foregroundNote: some View {
        let verdict = recorder.backgroundVerdict
        let tint = verdict.continuesInBackground ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)

        return Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(verdict.shortSummary)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(verdict.summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("Control Centre, the app switcher and a call banner are all fine either way.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: verdict.symbol)
                .foregroundStyle(tint)
        }
        .readoutCard(padding: 14)
        .accessibilityElement(children: .combine)
    }
}
