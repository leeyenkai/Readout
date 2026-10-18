import SwiftUI

/// One screen per reading: live value, chart, stats, comparisons and an explainer (R-24–R-28).
struct ReadingDetailView: View {
    let reading: ReadingID

    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @State private var isRunning = false

    private var descriptor: ReadingDescriptor { ReadingCatalog.descriptor(reading) }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch hub.availability(reading) {
                case .needsPermission(let permission):
                    PermissionCard(permission: permission, isDenied: false) {
                        await hub.permissions.request(permission)
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

                ExplainerCard(descriptor: descriptor)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .navigationTitle(descriptor.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { activateIfAllowed() }
        .onDisappear { deactivate() }
    }

    @ViewBuilder
    private var content: some View {
        if descriptor.requiresExplicitStart && !isRunning {
            ProximityStartCard(descriptor: descriptor) {
                isRunning = true
                hub.activate(reading, rate: .standard)
            }
        } else {
            LiveValuePanel(descriptor: descriptor, units: settings.displayUnits)

            if descriptor.isChartable {
                ReadingChartPanel(descriptor: descriptor, units: settings.displayUnits)
                StatsPanel(descriptor: descriptor, units: settings.displayUnits)
            }

            if let comparisons = descriptor.comparisons {
                ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
            }

            if descriptor.id == .acceleration {
                Toggle("Include gravity", isOn: Binding(
                    get: { settings.accelerationIncludesGravity },
                    set: { settings.accelerationIncludesGravity = $0 }
                ))
                .font(.subheadline)
                .padding(14)
                .glassEffect(.regular, in: .rect(cornerRadius: 18))
            }
        }
    }

    private func activateIfAllowed() {
        guard hub.availability(reading).isUsable else { return }
        guard !descriptor.requiresExplicitStart else { return }
        guard !isRunning else { return }
        isRunning = true
        hub.activate(reading, rate: .display)
    }

    private func deactivate() {
        guard isRunning else { return }
        isRunning = false
        hub.deactivate(reading, rate: descriptor.requiresExplicitStart ? .standard : .display)
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
            if let sample = hub.sample(descriptor.id) {
                values(for: sample)
                footnote(for: sample)
            } else {
                Text("Waiting for a reading…")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(height: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .contentShape(.rect)
        .onLongPressGesture {
            copy()
        }
        .sensoryFeedback(trigger: didCopy) { _, _ in
            settings.hapticsEnabled ? .success : nil
        }
        .overlay(alignment: .topTrailing) {
            if didCopy {
                Text("Copied")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .padding(10)
                    .transition(.opacity)
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
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .contentTransition(.numericText())
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
                .font(.system(.title2, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(formatted(value, channel: channel).symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func singleValue(channel: ReadingChannel, value: Double?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text((descriptor.estimateNote == nil ? "" : "≈") + formatted(value, channel: channel).text)
                .font(.system(size: 46, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
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
            // Every number says where it came from (P-2).
            Text(descriptor.source)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            if let note = sample.note ?? descriptor.estimateNote {
                Text(note)
                    .font(.caption2)
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
        didCopy = true
        withAnimation(.easeOut(duration: 0.3).delay(1.2)) { didCopy = false }
    }
}
