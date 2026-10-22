import Accessibility
import Charts
import SwiftUI

/// One saved recording: a chart and min/max/average per reading, with Rename, Delete and
/// Export (R-43, R-44).
struct RecordingSessionView: View {
    let session: RecordingSession
    /// Asked of the list that opened this, which leaves the screen before deleting: deleting
    /// from here let this view redraw with an object SwiftData had already thrown away.
    let onDelete: () -> Void

    @Environment(RecordingService.self) private var recorder
    @Environment(AppSettings.self) private var settings

    @State private var series: [ReadingID: RecordedSeries] = [:]
    @State private var hasLoaded = false
    @State private var isRenaming = false
    @State private var isConfirmingDelete = false
    @State private var newName = ""

    var body: some View {
        ReadoutScreen {
            header

            // Where a recording logged coordinates, the first thing worth seeing is where it
            // went — a latitude and a longitude as two traces say almost nothing (R-76).
            if !route.isEmpty {
                RoutePanel(route: route, drawsOn: true)
                    .transition(.blurReplace)
            }

            ForEach(Array(session.tracks.enumerated()), id: \.element.id) { index, track in
                TrackPanel(
                    track: track,
                    series: series[track.reading] ?? .empty,
                    units: settings.displayUnits
                )
                .arrival(delay: 0.05 * Double(index))
            }

            Text("Each reading is one CSV file: an ISO 8601 timestamp, elapsed seconds, then one column per value in the unit named in its header.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .motion(.readoutSmooth, value: hasLoaded)
        .navigationTitle("Recording")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                let files = recorder.fileURLs(for: session)
                // All of a session's CSV files go out together (R-44).
                ShareLink(items: files) { url in
                    SharePreview(url.lastPathComponent)
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(files.isEmpty)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Rename", systemImage: "pencil") {
                        newName = session.name
                        isRenaming = true
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        isConfirmingDelete = true
                    }
                }
            }
        }
        .alert("Rename recording", isPresented: $isRenaming) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") { recorder.rename(session, to: newName) }
                .disabled(!RecordingService.isValidName(newName))
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its CSV files are removed from this iPhone. Anything you have already exported is kept.")
        }
        .task(id: session.identifier) {
            await loadSeries()
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text(session.name)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(session.startedAt.formatted(date: .complete, time: .shortened))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("\(Duration.seconds(session.duration).formatted(.units(allowed: [.hours, .minutes, .seconds]))) · \(session.rate.summary) · \(RecordingNaming.sampleCountText(session.sampleCount)) · \(session.byteCount.formatted(.byteCount(style: .file)))")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if session.isInterrupted {
                // R-41: the recording stopped because the app went away.
                Label("Interrupted — Readout left the foreground while this was recording.", systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }
        }
        .readoutCard(padding: 18, alignment: .center)
    }

    /// The fixes this session logged, if it logged any (R-76).
    private var route: [RecordedCoordinate] {
        series[.coordinates]?.coordinates() ?? []
    }

    /// Reads the session's CSV files back for the charts. Parsing happens off the main actor
    /// because a long session is tens of thousands of rows.
    private func loadSeries() async {
        let files = session.tracks.map { track in
            (reading: track.reading, url: recorder.store.fileURL(for: track, in: session))
        }
        let parsed = await Task.detached(priority: .userInitiated) {
            var parsed: [ReadingID: RecordedSeries] = [:]
            for file in files {
                guard let series = RecordedSeries(contentsOf: file.url) else { continue }
                parsed[file.reading] = series
            }
            return parsed
        }.value
        // Arrives as one change, so the charts and the route fade in together rather than
        // popping in one after another.
        withReadoutAnimation(.readoutSmooth) {
            series = parsed
            hasLoaded = true
        }
    }
}

/// One reading inside a session: its chart, then its statistics (R-43).
private struct TrackPanel: View {
    let track: RecordedTrack
    let series: RecordedSeries
    let units: DisplayUnits

    @Environment(\.themeAccent) private var accent

    private var descriptor: ReadingDescriptor { track.descriptor }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: descriptor.name, symbol: descriptor.symbol) {
                Text(RecordingNaming.sampleCountText(track.sampleCount))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if descriptor.isChartable, !series.isEmpty {
                chart
                    .transition(.opacity)
            }

            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                if let summary = track.channels.indices.contains(index) ? track.channels[index] : nil {
                    HStack(spacing: 0) {
                        if descriptor.channels.count > 1 {
                            Text(channel.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(channel.axis?.colour ?? .secondary)
                                .frame(minWidth: 44, alignment: .leading)
                        }
                        // A channel that never had a value — no course while standing still
                        // the whole time — says so rather than showing zeros.
                        statistic("Min", summary.count > 0 ? summary.minimum : nil, channel: channel)
                        statistic("Max", summary.count > 0 ? summary.maximum : nil, channel: channel)
                        statistic("Avg", summary.count > 0 ? summary.mean : nil, channel: channel)
                    }
                }
            }

            Label(track.fileName, systemImage: "tablecells")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .readoutCard(padding: 14)
        .accessibilityElement(children: .contain)
        .accessibilityChartDescriptor(self)
    }

    private var chart: some View {
        Chart {
            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                let presentation = channel.unit.presentation(units)
                ForEach(series.points(channel: index)) { point in
                    LineMark(
                        x: .value("Seconds", point.elapsed),
                        y: .value(channel.name, presentation.convert(point.value)),
                        series: .value("Channel", channel.name)
                    )
                    .foregroundStyle(channel.axis?.colour ?? accent)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: channel.axis?.dash ?? []))
                    .interpolationMethod(.monotone)
                }
            }
        }
        // The same scale the live chart uses: fitted to the samples rather than reaching down
        // to zero, so a recording of air pressure is a trace and not a straight line (R-43).
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text("\(ValueFormatting.decimal(seconds, digits: 0)) s")
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
        .frame(height: 150)
        .accessibilityLabel("\(descriptor.name) over the whole recording")
    }

    /// The band the recorded samples occupy, with a little room above and below.
    private var yDomain: ClosedRange<Double> {
        var lowest = Double.greatestFiniteMagnitude
        var highest = -Double.greatestFiniteMagnitude
        for index in descriptor.channels.indices {
            let presentation = descriptor.channels[index].unit.presentation(units)
            for point in series.points(channel: index) {
                let value = presentation.convert(point.value)
                guard value.isFinite else { continue }
                lowest = min(lowest, value)
                highest = max(highest, value)
            }
        }
        guard lowest <= highest else { return -1...1 }
        let span = highest - lowest
        let padding = span > 0 ? span * 0.15 : max(abs(highest) * 0.01, 0.5)
        return (lowest - padding)...(highest + padding)
    }

    private var digits: Int {
        descriptor.channels.first?.unit.presentation(units).digits ?? 1
    }

    private func statistic(_ label: String, _ value: Double?, channel: ReadingChannel) -> some View {
        guard let value else {
            return StatColumn(label: label, text: "—", spoken: "no value recorded")
        }
        let formatted = ValueFormatting.format(value, unit: channel.unit, units: units)
        return StatColumn(label: label, text: formatted.text, spoken: formatted.spoken)
    }
}

extension TrackPanel: @MainActor AXChartDescriptorRepresentable {
    /// The recorded trace as an audio graph, the same as the live chart offers (R-52).
    func makeChartDescriptor() -> AXChartDescriptor {
        var lowest = Double.greatestFiniteMagnitude
        var highest = -Double.greatestFiniteMagnitude
        var longest: Double = 0

        let seriesDescriptors = descriptor.channels.enumerated().map { index, channel -> AXDataSeriesDescriptor in
            let presentation = channel.unit.presentation(units)
            let points = series.points(channel: index).map { point -> AXDataPoint in
                let value = presentation.convert(point.value)
                lowest = min(lowest, value)
                highest = max(highest, value)
                longest = max(longest, point.elapsed)
                return AXDataPoint(x: point.elapsed, y: value)
            }
            return AXDataSeriesDescriptor(name: channel.name, isContinuous: true, dataPoints: points)
        }

        let floor = lowest <= highest ? lowest : 0
        let ceiling = highest > floor ? highest : floor + 1
        let digits = digits

        return AXChartDescriptor(
            title: descriptor.name,
            summary: descriptor.estimateNote,
            xAxis: AXNumericDataAxisDescriptor(
                title: "Seconds into the recording",
                range: 0...(longest > 0 ? longest : 1),
                gridlinePositions: []
            ) { "\(ValueFormatting.decimal($0, digits: 0)) seconds" },
            yAxis: AXNumericDataAxisDescriptor(
                title: descriptor.name,
                range: floor...ceiling,
                gridlinePositions: []
            ) { value in
                let symbol = descriptor.channels.first?.unit.presentation(units).symbol ?? ""
                return "\(ValueFormatting.decimal(value, digits: digits)) \(symbol)"
            },
            series: seriesDescriptors
        )
    }

    func updateChartDescriptor(_ descriptor: AXChartDescriptor) {
        // Rebuilt from the parsed series whenever VoiceOver asks.
    }
}
