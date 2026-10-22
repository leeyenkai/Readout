import SwiftUI

/// The moment a recording is saved: a tick drawn on, and where to find it. Stopping used to
/// end with nothing but a haptic and the bar sliding away (R-40, R-42).
struct SavedToast: View {
    let recording: SavedRecording

    @State private var showsTick = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if showsTick {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.green)
                        .transition(.symbolEffect(.drawOn))
                }
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text("Recording saved")
                    .font(.subheadline.weight(.semibold))
                Text("In Recordings")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 6)
        .onAppear {
            withReadoutAnimation(.readoutSpring) { showsTick = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording saved, in Recordings")
    }
}
