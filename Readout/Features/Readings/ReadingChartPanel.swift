import Accessibility
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
    @Environment(\.themeAccent) private var accent
    @State private var window: ChartWindow = .tenSeconds
    @State private var isPaused = false
    @State private var hiddenChannels: Set<Int> = []
    @State private var frozen: [SensorSample] = []
    @State private var scale = ChartScale()

    var body: some View {
        let source = source
        let domain = domain(for: source)

        VStack(spacing: 12) {
            header

            Chart {
                ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                    if !hiddenChannels.contains(index) {
                        ForEach(points(channel: index, from: source), id: \.time) { point in
                            LineMark(
                                x: .value("Time", point.time),
                                y: .value(channel.name, point.value),
                                series: .value("Channel", channel.name)
                            )
                            .foregroundStyle(channel.axis?.colour ?? accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: channel.axis?.dash ?? []))
                            .interpolationMethod(.monotone)
                        }
                    }
                }
            }
            // A fixed window ending at the newest sample, so the trace scrolls leftwards at
            // a constant scale rather than the axis stretching to fit whatever has arrived
            // so far — and so the labels below mean the same thing from one second to the
            // next (R-25).
            .chartXScale(domain: domain)
            // And a vertical scale that fits what is on screen rather than reaching down to
            // zero: air pressure only ever moves between about 1,000 and 1,030 hPa, and on an
            // axis that starts at nothing it draws as a dead flat line (R-25).
            .chartYScale(domain: scale.domain ?? yDomain(for: source))
            .chartXAxis {
                AxisMarks(values: marks(in: domain)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(ValueFormatting.relativeTime(
                                secondsAgo: domain.upperBound.timeIntervalSince(date)
                            ))
                            .font(.caption2)
                        }
                    }
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
            // A different window zooms the trace out or in rather than replacing it, and an
            // axis switched off fades away.
            .motion(.readoutSmooth, value: window)
            .motion(.readoutSnappy, value: hiddenChannels)

            if descriptor.isMultiAxis {
                axisToggles
            }
        }
        .readoutCard(padding: 14)
        .onChange(of: source.last?.time, initial: true) { _, _ in updateScale() }
        .onChange(of: window) { _, _ in
            scale.reset()
            updateScale()
        }
        .onChange(of: hiddenChannels) { _, _ in
            scale.reset()
            updateScale()
        }
        .accessibilityLabel("\(descriptor.name) chart, last \(window.title)")
        // VoiceOver's Audio Graph: the shape of the trace as a tone that rises and falls,
        // so a chart is not simply unavailable without sight (R-52).
        .accessibilityChartDescriptor(self)
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
                    .frame(width: 30, height: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel(isPaused ? "Resume the chart" : "Pause the chart")
        }
    }

    private var axisToggles: some View {
        HStack(spacing: 8) {
            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                let isHidden = hiddenChannels.contains(index)
                Button {
                    // A chart with every axis switched off says nothing; the last one stays.
                    if isHidden {
                        hiddenChannels.remove(index)
                    } else if hiddenChannels.count < descriptor.channels.count - 1 {
                        hiddenChannels.insert(index)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(channel.axis?.colour ?? accent)
                            .frame(width: 8, height: 8)
                        Text(channel.name)
                            .font(.caption.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .opacity(isHidden ? 0.4 : 1)
                .motion(.readoutSnappy, value: isHidden)
                .accessibilityLabel(isHidden ? "Show \(channel.name)" : "Hide \(channel.name)")
            }
            Spacer()
        }
    }

    private var samples: [SensorSample] {
        hub.buffer(descriptor.id).samples(in: window.duration)
    }

    /// Rotating and filtering the ring is the expensive part, so it happens once per redraw
    /// rather than once per channel — three axes used to walk the whole buffer three times.
    private var source: [SensorSample] {
        isPaused ? frozen : samples
    }

    /// The window the chart draws, ending at the newest sample it has.
    private func domain(for source: [SensorSample]) -> ClosedRange<Date> {
        let end = source.last?.time ?? .now
        return end.addingTimeInterval(-window.duration)...end
    }

    /// The band the visible samples occupy, before the scale has settled on one.
    private func yDomain(for source: [SensorSample]) -> ClosedRange<Double> {
        guard let extent = extent(of: source) else { return -1...1 }
        return ChartScale.niceDomain(lowest: extent.lowest, highest: extent.highest)
    }

    /// Moves the settled scale on with what is now on screen.
    private func updateScale() {
        guard let extent = extent(of: source) else { return }
        scale.update(lowest: extent.lowest, highest: extent.highest, at: .now)
    }

    /// The lowest and highest visible values, in the units shown.
    private func extent(of source: [SensorSample]) -> (lowest: Double, highest: Double)? {
        var lowest = Double.greatestFiniteMagnitude
        var highest = -Double.greatestFiniteMagnitude
        for index in descriptor.channels.indices where !hiddenChannels.contains(index) {
            let presentation = descriptor.channels[index].unit.presentation(units)
            for sample in source {
                guard let value = sample.value(index) else { continue }
                let converted = presentation.convert(value)
                guard converted.isFinite else { continue }
                lowest = min(lowest, converted)
                highest = max(highest, converted)
            }
        }
        guard lowest <= highest else { return nil }
        return (lowest, highest)
    }

    /// Three marks — the start of the window, its middle and now — rather than whatever
    /// wall-clock boundaries an automatic Date axis would pick.
    private func marks(in domain: ClosedRange<Date>) -> [Date] {
        [
            domain.lowerBound,
            domain.lowerBound.addingTimeInterval(window.duration / 2),
            domain.upperBound,
        ]
    }

    private func points(channel: Int, from source: [SensorSample]) -> [ChartPoint] {
        let unit = descriptor.channels[channel].unit
        let presentation = unit.presentation(units)
        return source.compactMap { sample in
            // A missing value — no course while standing still — is published as NaN, which a
            // line mark cannot draw (R-45).
            guard let value = sample.value(channel), value.isFinite else { return nil }
            return ChartPoint(time: sample.time, value: presentation.convert(value))
        }
    }

    private var digits: Int {
        descriptor.channels.first?.unit.presentation(units).digits ?? 1
    }

    /// Seconds before now, which is what an audio graph's x axis should say: "6 seconds ago"
    /// means something spoken, where an absolute timestamp does not.
    private func secondsAgo(_ sample: SensorSample, from latest: Date) -> Double {
        latest.timeIntervalSince(sample.time)
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

extension ReadingChartPanel: @MainActor AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor {
        let source = source
        let latest = source.last?.time ?? .now
        let presentation = descriptor.channels.first?.unit.presentation(units)

        var lowest = Double.greatestFiniteMagnitude
        var highest = -Double.greatestFiniteMagnitude

        let series = descriptor.channels.enumerated().compactMap { index, channel -> AXDataSeriesDescriptor? in
            guard !hiddenChannels.contains(index) else { return nil }
            let conversion = channel.unit.presentation(units)
            let points = source.compactMap { sample -> AXDataPoint? in
                guard let value = sample.value(index) else { return nil }
                let converted = conversion.convert(value)
                guard converted.isFinite else { return nil }
                lowest = min(lowest, converted)
                highest = max(highest, converted)
                return AXDataPoint(x: -secondsAgo(sample, from: latest), y: converted)
            }
            return AXDataSeriesDescriptor(name: channel.name, isContinuous: true, dataPoints: points)
        }

        // A flat trace, or no trace at all, would be a zero-width range, which the audio
        // graph cannot sweep through.
        let floor = lowest <= highest ? lowest : 0
        let ceiling = highest > floor ? highest : floor + 1
        let digits = digits

        return AXChartDescriptor(
            title: "\(descriptor.name), last \(window.title)",
            summary: descriptor.estimateNote,
            xAxis: AXNumericDataAxisDescriptor(
                title: "Seconds ago",
                range: -window.duration...0,
                gridlinePositions: []
            ) { "\(ValueFormatting.decimal(-$0, digits: 1)) seconds ago" },
            yAxis: AXNumericDataAxisDescriptor(
                title: descriptor.name,
                range: floor...ceiling,
                gridlinePositions: []
            ) { value in
                "\(ValueFormatting.decimal(value, digits: digits)) \(presentation?.symbol ?? "")"
            },
            series: series
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // The descriptor is rebuilt from the live buffer each time VoiceOver asks for it.
    }
}
