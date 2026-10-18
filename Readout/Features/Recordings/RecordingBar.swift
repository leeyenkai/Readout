import SwiftUI

/// The compact bar shown while a recording runs: elapsed time, sample count and Stop (R-40).
struct RecordingBar: View {
    @Environment(RecordingService.self) private var recorder
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
                Text("\(RecordingNaming.sampleCountText(recorder.sampleCount)) · \(recorder.rate.title)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button("Stop") {
                recorder.stop()
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording, \(RecordingNaming.elapsedText(recorder.elapsed)), \(RecordingNaming.sampleCountText(recorder.sampleCount))")
    }
}
