import SwiftUI

/// Shown once, the first time Readout opens: what it measures, which numbers are estimates,
/// and where the data goes (R-73).
///
/// Three short points rather than a tour. The point is to set expectations before the first
/// permission prompt arrives — above all that sound and light are worked out indirectly, so
/// a reading that disagrees with a proper meter is the app being honest, not broken (P-2).
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShown = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        ReadoutMark(isDrawn: isShown)
                            .frame(width: 84, height: 84)
                        Text("Readout")
                            .font(.largeTitle.weight(.bold))
                        Text("What your iPhone can already sense, with every number saying where it comes from.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 12)

                    point(
                        0,
                        symbol: "square.grid.2x2",
                        title: "\(ReadingCatalog.all.count) readings, \(Self.instrumentCount) instruments",
                        body: "Motion, environment, location and the phone itself — each with a live chart, an explainer and everyday comparisons. Tap a tile to open it."
                    )
                    point(
                        1,
                        symbol: "wave.3.right",
                        title: "Sound and light are estimates",
                        body: "iOS keeps the ambient light sensor to itself, so light is worked out from the camera's exposure and sound from the microphone's level. Both carry a “≈”, and both can be calibrated against a real meter."
                    )
                    point(
                        2,
                        symbol: "hand.raised",
                        title: "Nothing leaves this iPhone",
                        body: "No accounts and no analytics. Audio and camera frames are read in memory and never saved, and a sensor runs only while you look at it or record it."
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                // The padding belongs inside the button, on the label: applied outside it,
                // it enlarged the tap target without enlarging the glass capsule, so the
                // control was thinner than the area that answered a tap.
                Button {
                    dismiss()
                } label: {
                    Text("Start")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .opacity(isShown ? 1 : 0)
                .offset(y: isShown ? 0 : 20)
            }
            .themedSurface()
            .onAppear {
                guard !isShown else { return }
                withReadoutAnimation(.readoutSmooth) { isShown = true }
            }
        }
    }

    /// "five instruments" rather than "5 instruments", counted from the tools themselves so
    /// the sentence cannot fall out of date.
    private static var instrumentCount: String {
        let words = ["no", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]
        let count = Tool.allCases.count
        return words.indices.contains(count) ? words[count] : "\(count)"
    }

    private func point(_ index: Int, symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 34)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // The points follow the mark in, one after another.
        .opacity(isShown ? 1 : 0)
        .offset(y: isShown ? 0 : 16)
        .animation(UIAccessibility.isReduceMotionEnabled ? nil : .readoutSmooth.delay(0.55 + Double(index) * 0.12), value: isShown)
    }
}

/// The app icon's mark — a rising trace with a live point at its end — drawn on as the
/// welcome screen opens, in the theme's accent.
private struct ReadoutMark: View {
    let isDrawn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The trace's corners, from the icon's artwork, on its 1024-point canvas.
    private static let corners: [CGPoint] = [
        CGPoint(x: 176, y: 712), CGPoint(x: 312, y: 628), CGPoint(x: 416, y: 772),
        CGPoint(x: 560, y: 420), CGPoint(x: 688, y: 524), CGPoint(x: 812, y: 322),
    ]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let scale = side / 1024
            let end = Self.corners[Self.corners.count - 1]
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(.tint.opacity(0.16))
                Trace(corners: Self.corners, scale: scale)
                    .trim(from: 0, to: isDrawn || reduceMotion ? 1 : 0)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 88 * scale, lineCap: .round, lineJoin: .round))
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9).delay(0.1), value: isDrawn)
                Circle()
                    .fill(.white)
                    .frame(width: 168 * scale, height: 168 * scale)
                    .position(x: end.x * scale, y: end.y * scale)
                    .scaleEffect(isDrawn || reduceMotion ? 1 : 0.01, anchor: UnitPoint(x: end.x / 1024, y: end.y / 1024))
                    .animation(reduceMotion ? nil : .readoutSpring.delay(0.95), value: isDrawn)
            }
            .frame(width: side, height: side)
        }
        .accessibilityHidden(true)
    }

    private struct Trace: Shape {
        let corners: [CGPoint]
        let scale: CGFloat

        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.addLines(corners.map { CGPoint(x: $0.x * scale, y: $0.y * scale) })
            return path
        }
    }
}
