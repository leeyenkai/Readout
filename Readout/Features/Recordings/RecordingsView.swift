import SwiftUI

/// Recording and CSV export are the next milestone (SPEC §8, v0.2.0). Until then this tab
/// says so plainly rather than offering a button that does nothing.
struct RecordingsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 48)

                    Text("Recording is not here yet")
                        .font(.title3.weight(.semibold))

                    Text("The next version logs the readings you choose while the app is open, saves each session on this iPhone, and exports it as CSV through the share sheet.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

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
            .navigationTitle("Recordings")
        }
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
