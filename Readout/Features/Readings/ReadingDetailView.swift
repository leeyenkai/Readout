import SwiftUI

/// One screen per reading: live value, chart, stats, comparisons and an explainer (R-24–R-28).
struct ReadingDetailView: View {
    let reading: ReadingID

    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder
    @State private var isRunning = false
    @State private var lease: SensorLease?
    /// A permission granted while this sits in a hidden tab must not start the reading there.
    @State private var isVisible = false

    private var descriptor: ReadingDescriptor { ReadingCatalog.descriptor(reading) }

    var body: some View {
        ReadoutScreen {
            Group {
                switch hub.availability(reading) {
                case .needsPermission(let permission):
                    PermissionCard(permission: permission, isDenied: false) {
                        await hub.requestPermission(permission)
                        activateIfAllowed()
                    }
                case .denied(let permission):
                    PermissionCard(permission: permission, isDenied: true) {
                        hub.permissions.openSettings()
                    }
                case .unavailable:
                    UnavailableCard(name: descriptor.name)
                case .live, .ready:
                    content
                }
            }
            .motion(.readoutSmooth, value: hub.availability(reading).isUsable)
            .motion(.readoutSmooth, value: isRunning)

            ExplainerCard(descriptor: descriptor)
        }
        .navigationTitle(descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [reading])
            }
        }
        .onAppear {
            isVisible = true
            activateIfAllowed()
        }
        .onDisappear {
            isVisible = false
            deactivate()
        }
        // A permission granted here — or in the Settings app while this screen was open —
        // starts the reading. Waiting for the card's own request was not enough: Core
        // Location answers later, by which time nothing was left to start it.
        .onChange(of: hub.availability(reading).isUsable) { _, isUsable in
            if isUsable { activateIfAllowed() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if descriptor.requiresExplicitStart && !isRunning {
            ProximityStartCard(descriptor: descriptor) {
                isRunning = true
                lease = hub.activate(reading, rate: .standard)
                hub.resetStats(reading)
            }
        } else {
            LiveValuePanel(descriptor: descriptor, units: settings.displayUnits)
                .transition(.blurReplace)

            readingControls

            if descriptor.isChartable {
                ReadingChartPanel(descriptor: descriptor, units: settings.displayUnits)
                StatsPanel(descriptor: descriptor, units: settings.displayUnits)
            }

            if let comparisons = descriptor.comparisons {
                ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
            }
        }
    }

    /// The few controls that belong to one reading, beside the value they change.
    @ViewBuilder
    private var readingControls: some View {
        if descriptor.id == .orientation {
            // Pitch, roll and yaw are three numbers; the Attitude tool is the same reading as
            // a phone you can see turn (R-86).
            NavigationLink(value: Tool.attitude) {
                HStack(spacing: 12) {
                    Image(systemName: Tool.attitude.symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                        .background(.tint.opacity(0.14), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("See it in 3D")
                            .font(.subheadline.weight(.semibold))
                        Text("A model of your phone that turns as it does")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .readoutCard(padding: 14)
            }
            .buttonStyle(.pressableCard)
        }
        if descriptor.id == .acceleration {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Include gravity", isOn: Binding(
                    get: { settings.accelerationIncludesGravity },
                    set: { settings.accelerationIncludesGravity = $0 }
                ))
                .font(.subheadline.weight(.medium))
                // A recording's acceleration column means one thing from start to finish
                // (R-30, R-45).
                .disabled(recorder.isRecording(.acceleration))
                if recorder.isRecording(.acceleration) {
                    Text("Fixed while a recording is logging acceleration.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .readoutCard(padding: 14)
        }
    }

    private func activateIfAllowed() {
        guard isVisible, hub.availability(reading).isUsable else { return }
        guard !descriptor.requiresExplicitStart else { return }
        guard lease == nil else { return }
        isRunning = true
        lease = hub.activate(reading, rate: .display)
        // "Since you opened this" means since now. The history behind the chart is kept, but
        // the statistics used to reach back to whenever the reading first ran.
        hub.resetStats(reading)
    }

    private func deactivate() {
        isRunning = false
        hub.release(lease)
        lease = nil
    }
}

/// The large live value at the top, per axis where a reading has axes (R-24, R-31).
private struct LiveValuePanel: View {
    let descriptor: ReadingDescriptor
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @State private var didCopy = false

    var body: some View {
        VStack(spacing: 10) {
            // A reading that has stopped arriving says so rather than holding the last
            // number on screen, which stopped being true the moment the sensor stopped (P-2).
            if let stalled = hub.stalledReason(descriptor.id) {
                Label(stalled, systemImage: "pause.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 60)
                    .transition(.blurReplace)
            } else if let sample = hub.sample(descriptor.id) {
                values(for: sample)
                    .transition(.blurReplace)
                footnote(for: sample)
            } else {
                WaitingLabel(text: "Waiting for a reading…")
                    .transition(.blurReplace)
            }
        }
        .motion(.readoutSnappy, value: hub.sample(descriptor.id) == nil)
        .motion(.readoutSnappy, value: hub.stalledReason(descriptor.id))
        .padding(.vertical, 6)
        .readoutCard(padding: 18, alignment: .center)
        .contentShape(.rect)
        .onLongPressGesture {
            copy()
        }
        // Only as the value is copied. Keying on any change of `didCopy` tapped a second time
        // as the "Copied" badge faded out, which is not an event worth feeling.
        .sensoryFeedback(trigger: didCopy) { _, copied in
            settings.hapticsEnabled && copied ? .success : nil
        }
        .overlay(alignment: .topTrailing) {
            if didCopy {
                StatusBadge(text: "Copied", symbol: "doc.on.doc.fill")
                    .padding(10)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Long press to copy the value")
    }

    @ViewBuilder
    private func values(for sample: SensorSample) -> some View {
        switch descriptor.kind {
        case .discrete:
            Text(sample.state ?? "—")
                .readoutValue(size: 44)
                .contentTransition(.interpolate)
                .motion(.readoutSnappy, value: sample.state)
        case .coordinates:
            Text(coordinateText(sample))
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
        case .continuous:
            if descriptor.isMultiAxis {
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                        axisValue(channel: channel, value: sample.value(index))
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                        if index > 0 {
                            Text("·")
                                .font(.title3)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                        }
                        singleValue(channel: channel, value: sample.value(index))
                    }
                }
            }
        }
    }

    private func axisValue(channel: ReadingChannel, value: Double?) -> some View {
        VStack(spacing: 2) {
            Text(channel.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(channel.axis?.colour ?? .secondary)
            Text(formatted(value, channel: channel).text)
                .readoutValue(size: 28)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(formatted(value, channel: channel).symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func singleValue(channel: ReadingChannel, value: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            let text = (descriptor.estimateNote == nil ? "" : "≈") + formatted(value, channel: channel).text
            Text(text)
                .readoutValue(size: 48)
                .monospacedDigit()
                .contentTransition(.numericText())
                // Slow readings roll their digits; fast ones hold still (see `updatesSlowly`).
                .motion(.readoutSnappy, value: descriptor.updatesSlowly ? text : "")
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(formatted(value, channel: channel).symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func footnote(for sample: SensorSample) -> some View {
        VStack(spacing: 2) {
            // Every number says where it came from (P-2), and an estimate says so whatever
            // the provider's own note adds — the two used to replace each other.
            Text(descriptor.source)
                .font(.caption)
                .foregroundStyle(.secondary)
            let notes = [sample.note, descriptor.estimateNote]
                .compactMap { $0 }
                .reduce(into: [String]()) { notes, note in
                    if !notes.contains(where: { $0.localizedCaseInsensitiveContains(note) || note.localizedCaseInsensitiveContains($0) }) {
                        notes.append(note)
                    }
                }
            if !notes.isEmpty {
                Text(notes.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
    }

    private func formatted(_ value: Double?, channel: ReadingChannel) -> ValueFormatting.Formatted {
        guard let value else { return ValueFormatting.Formatted(text: "—", symbol: "") }
        return ValueFormatting.format(value, unit: channel.unit, units: units)
    }

    private func coordinateText(_ sample: SensorSample) -> String {
        guard sample.values.count >= 2 else { return "—" }
        return ValueFormatting.coordinate(
            latitude: sample.values[0],
            longitude: sample.values[1],
            format: units.coordinates
        )
    }

    /// Long-pressing the live value copies it with its unit (R-31).
    private func copy() {
        guard let sample = hub.sample(descriptor.id) else { return }
        let text: String
        switch descriptor.kind {
        case .discrete:
            text = sample.state ?? "—"
        case .coordinates:
            text = coordinateText(sample)
        case .continuous:
            text = descriptor.channels.enumerated().map { index, channel in
                let value = formatted(sample.value(index), channel: channel)
                return descriptor.isMultiAxis ? "\(channel.name) \(value.spoken)" : value.spoken
            }
            .joined(separator: "  ")
        }
        UIPasteboard.general.string = text
        withReadoutAnimation { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withReadoutAnimation { didCopy = false }
        }
    }
}
