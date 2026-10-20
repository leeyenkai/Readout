import SwiftUI

/// The Tools tab: four full-screen instruments (R-32–R-35).
struct ToolsView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(Tool.allCases) { tool in
                        NavigationLink(value: tool) {
                            ToolRow(tool: tool)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Tools")
            .navigationDestination(for: Tool.self) { tool in
                switch tool {
                case .level: SpiritLevelView()
                case .compass: CompassToolView()
                case .soundMeter: SoundMeterView()
                case .lightMeter: LightMeterView()
                }
            }
            .themedSurface()
        }
    }
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case level, compass, soundMeter, lightMeter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .level: "Spirit level"
        case .compass: "Compass"
        case .soundMeter: "Sound meter"
        case .lightMeter: "Light meter"
        }
    }

    var subtitle: String {
        switch self {
        case .level: "Bubble and angle, to a tenth of a degree"
        case .compass: "Heading, with a bearing you can lock"
        case .soundMeter: "Current, peak and average dB"
        case .lightMeter: "Approximate lux from the camera"
        }
    }

    var symbol: String {
        switch self {
        case .level: "level"
        case .compass: "location.north.circle"
        case .soundMeter: "waveform"
        case .lightMeter: "sun.max"
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
                .frame(width: 36)
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
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}
