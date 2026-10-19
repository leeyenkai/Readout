import SwiftUI

/// Shown once, the first time Readout opens: what it measures, which numbers are estimates,
/// and where the data goes (R-73).
///
/// Three short cards rather than a tour. The point is to set expectations before the first
/// permission prompt arrives — above all that sound and light are worked out indirectly, so
/// a reading that disagrees with a proper meter is the app being honest, not broken (P-2).
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Readout shows what your iPhone can already sense, and says where every number comes from.")
                        .font(.title3)
                        .padding(.bottom, 4)

                    card(
                        symbol: "square.grid.2x2",
                        title: "\(ReadingCatalog.all.count) readings and four instruments",
                        body: "Motion, environment, location and the device itself, each with a live chart, "
                            + "its own explainer and a scale of everyday comparisons. Tap a tile to open it."
                    )

                    card(
                        symbol: "wave.3.right",
                        title: "Sound and light are estimates",
                        body: "iOS keeps the ambient light sensor to itself and exposes no thermometer at all. "
                            + "Readout works light out from the camera's exposure and sound from the microphone's "
                            + "level, so both carry a “≈” and neither is a calibrated measurement."
                    )

                    card(
                        symbol: "hand.raised",
                        title: "Nothing leaves this iPhone",
                        body: "No accounts, no analytics, no network requests at all. Microphone audio and camera "
                            + "frames are read in memory to work out a level and are never saved. A sensor runs "
                            + "only while you are looking at it or recording it."
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Start") { dismiss() }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .buttonStyle(.glassProminent)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
            }
        }
    }

    private func card(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
