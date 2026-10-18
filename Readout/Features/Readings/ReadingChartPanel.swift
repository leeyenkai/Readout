import Charts
import SwiftUI

/// The live chart: 10 s by default, switchable to 1 min and 5 min, pausable, with per-axis
/// toggles (R-25).
///
/// A separate view from the live value so it only redraws when the history buffer changes,
/// at the 10 Hz the buffer decimates to, rather than at sensor rate.
struct ReadingChartPanel: View {
    let descriptor: ReadingDescriptor
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub
    @State private var window: ChartWindow = .tenSeconds
    @State private var isPaused = false
    @State private var hiddenChannels: Set<Int> = []
    @State private var frozen: [SensorSample] = []

    var body: some View {
        VStack(spacing: 12) {
            header

            Chart {
                ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                    if !hiddenChannels.contains(index) {
                        ForEach(points(channel: index), id: \.time) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value(channel.name, point.value),
                                series: .value("Channel", channel.name)
                            )
                            .foregroundStyle(channel.axis?.colour ?? Color.accentColor)
                            .interpolationMethod(.monotone)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) {
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let number = value.as(Double.self) {
                            Text(ValueFormatting.decimal(number, digits: digits))
                                .font(.caption2)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 170)

            if descriptor.isMultiAxis {
                axisToggles
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityLabel("\(descriptor.name) chart, last \(window.title)")
    }

    private var header: some View {
        HStack {
            Picker("Window", selection: $window) {
                ForEach(ChartWindow.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Button {
                isPaused.toggle()
                frozen = isPaused ? samples : []
            } label: {
                Image(systemName: isPaused ? "play.fill" : "pause.fill")
                    .font(.footnote.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.glass)
            .accessibilityLabel(isPaused ? "Resume the chart" : "Pause the chart")
        }
    }

    private var axisToggles: some View {
        HStack(spacing: 8) {
            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                let isHidden = hiddenChannels.contains(index)
                Button {
                    if isHidden {
                        hiddenChannels.remove(index)
                    } else {
                        hiddenChannels.insert(index)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(channel.axis?.colour ?? Color.accentColor)
                            .frame(width: 8, height: 8)
                        Text(channel.name)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .opacity(isHidden ? 0.4 : 1)
                .accessibilityLabel(isHidden ? "Show \(channel.name)" : "Hide \(channel.name)")
            }
            Spacer()
        }
    }

    private var samples: [SensorSample] {
        hub.buffer(descriptor.id).samples(in: window.duration)
    }

    private func points(channel: Int) -> [ChartPoint] {
        let source = isPaused ? frozen : samples
        let unit = descriptor.channels[channel].unit
        let presentation = unit.presentation(units)
        return source.compactMap { sample in
            guard let value = sample.value(channel) else { return nil }
            return ChartPoint(time: sample.time, value: presentation.convert(value))
        }
    }

    private var digits: Int {
        descriptor.channels.first?.unit.presentation(units).digits ?? 1
    }
}

private struct ChartPoint: Identifiable {
    let time: Date
    let value: Double
    var id: Date { time }
}

enum ChartWindow: String, CaseIterable, Identifiable {
    case tenSeconds, oneMinute, fiveMinutes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tenSeconds: "10 s"
        case .oneMinute: "1 min"
        case .fiveMinutes: "5 min"
        }
    }

    var duration: TimeInterval {
        switch self {
        case .tenSeconds: 10
        case .oneMinute: 60
        case .fiveMinutes: 300
        }
    }
}
