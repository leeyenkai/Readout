import SwiftUI

/// The Tools tab: the full-screen instruments (R-32–R-35, R-86).
struct ToolsView: View {
    @Namespace private var zoom

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Array(Tool.allCases.enumerated()), id: \.element) { index, tool in
                        NavigationLink(value: tool) {
                            ToolRow(tool: tool)
                                .matchedTransitionSource(id: tool, in: zoom)
                        }
                        .buttonStyle(.pressableCard)
                        .arrival(delay: Double(index) * 0.05)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, Metrics.bottomPadding)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Tools")
            .navigationDestination(for: Tool.self) { tool in
                tool.destination
                    .navigationTransition(.zoom(sourceID: tool, in: zoom))
            }
            .themedSurface()
        }
    }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case attitude, level, compass, soundMeter, lightMeter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attitude: "Attitude"
        case .level: "Spirit level"
        case .compass: "Compass"
        case .soundMeter: "Sound meter"
        case .lightMeter: "Light meter"
        }
    }

    var subtitle: String {
        switch self {
        case .attitude: "Your phone in 3D, turning as it does"
        case .level: "Bubble and angle, to a tenth of a degree"
        case .compass: "Heading, with a bearing you can lock"
        case .soundMeter: "Current, peak and average dB"
        case .lightMeter: "Approximate lux from the camera"
        }
    }

    var symbol: String {
        switch self {
        case .attitude: "iphone.gen3.motion"
        case .level: "level"
        case .compass: "location.north.circle"
        case .soundMeter: "waveform"
        case .lightMeter: "sun.max"
        }
    }

    /// The screen a tool opens. Kept here so any navigation stack — the Tools tab, or a
    /// reading's detail view linking to its instrument — can push one.
    @ViewBuilder @MainActor
    var destination: some View {
        switch self {
        case .attitude: AttitudeToolView()
        case .level: SpiritLevelView()
        case .compass: CompassToolView()
        case .soundMeter: SoundMeterView()
        case .lightMeter: LightMeterView()
        }
    }
}

private struct ToolRow: View {
    let tool: Tool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: tool.symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.headline)
                Text(tool.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(Metrics.cardPadding)
        .contentShape(.rect(cornerRadius: Metrics.cardRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}
