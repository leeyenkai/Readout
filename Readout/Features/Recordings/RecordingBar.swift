import SwiftUI

/// The compact bar shown while a recording runs: elapsed time, sample count and Stop (R-40).
struct RecordingBar: View {
    @Environment(RecordingService.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isShowingSession = false

    var body: some View {
        HStack(spacing: 10) {
            // The bar itself opens the running session, so what is being logged is one tap
            // away from wherever the user happens to be (R-79). Stop stays a button of its
            // own: it is not something to reach by accident.
            Button {
                isShowingSession = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "record.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse, isActive: !reduceMotion)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(RecordingNaming.elapsedText(recorder.elapsed))
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .motion(.readoutSnappy, value: recorder.elapsed)
                        Text("\(RecordingNaming.sampleCountText(recorder.sampleCount)) · \(recorder.rate.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // A session stops itself at its limit, so it says so before it gets
                        // there rather than ending without warning (Q-4).
                        if isNearLimit {
                            Text("Nearing the recording limit")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                                .transition(.blurReplace)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Recording, \(RecordingNaming.elapsedText(recorder.elapsed)), \(RecordingNaming.sampleCountText(recorder.sampleCount))")
            .accessibilityHint(isNearLimit ? "Nearing the recording limit. Opens the running recording." : "Opens the running recording")

            // The same red Stop as the running recording's own screen.
            Button("Stop", systemImage: "stop.fill", role: .destructive) {
                recorder.stop()
            }
            .labelStyle(.titleAndIcon)
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
            .tint(.red)
        }
        .motion(.readoutSnappy, value: isNearLimit)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .sheet(isPresented: $isShowingSession) {
            LiveRecordingView()
        }
    }

    private var isNearLimit: Bool { recorder.limitFraction >= 0.8 }
}
