import SwiftUI

/// Minimum, maximum and mean since the view opened, with a reset (R-26).
struct StatsPanel: View {
    let descriptor: ReadingDescriptor
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub

    var body: some View {
        VStack(spacing: 12) {
            CardHeader(title: "Since you opened this") {
                Button("Reset") {
                    withReadoutAnimation { hub.resetStats(descriptor.id) }
                }
                .font(.footnote.weight(.semibold))
            }

            let buffer = hub.buffer(descriptor.id)
            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                HStack(spacing: 0) {
                    if descriptor.channels.count > 1 {
                        Text(channel.name)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(channel.axis?.colour ?? .secondary)
                            .frame(minWidth: 44, alignment: .leading)
                    }
                    let stats = buffer.stats(channel: index)
                    statistic("Min", stats?.minimum, channel: channel)
                    statistic("Max", stats?.maximum, channel: channel)
                    statistic("Avg", stats?.mean, channel: channel)
                }
            }
        }
        .readoutCard(padding: 14)
    }

    private func statistic(_ label: String, _ value: Double?, channel: ReadingChannel) -> some View {
        guard let value else {
            return StatColumn(label: label, text: "—", spoken: "no reading yet")
        }
        let formatted = ValueFormatting.format(value, unit: channel.unit, units: units)
        return StatColumn(label: label, text: formatted.text, spoken: formatted.spoken)
    }
}

/// The current value placed on a bar of everyday references (R-27).
struct ComparisonPanel: View {
    let descriptor: ReadingDescriptor
    let scale: ComparisonScale
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "How that compares", symbol: "ruler")

            ComparisonBar(scale: scale, value: currentValue)

            Group {
                if let nearest = currentValue.flatMap(scale.nearest(to:)) {
                    Text("About the same as \(nearest.label.lowercased())")
                        .foregroundStyle(nearest.caution ? .orange : .primary)
                        .id(nearest.label)
                } else {
                    Text("Between the everyday references")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline.weight(.medium))
            .transition(.blurReplace)
            .motion(.readoutSnappy, value: currentValue.flatMap(scale.nearest(to:))?.label)

            FlowRow(spacing: 6) {
                ForEach(scale.references) { reference in
                    let formatted = ValueFormatting.format(reference.value, unit: unit, units: units)
                    Text("\(formatted.spoken) \(reference.label.lowercased())")
                        .font(.caption2)
                        .foregroundStyle(reference.caution ? .orange : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary.opacity(0.5), in: .capsule)
                }
            }
        }
        .readoutCard(padding: 14)
    }

    private var unit: ValueUnit {
        descriptor.channels.first?.unit ?? .none
    }

    private var currentValue: Double? {
        hub.sample(descriptor.id).flatMap(descriptor.summaryValue).flatMap { $0.isFinite ? $0 : nil }
    }
}

struct ComparisonBar: View {
    let scale: ComparisonScale
    let value: Double?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: 8)

                ForEach(scale.references) { reference in
                    Capsule()
                        .fill(reference.caution ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: 14)
                        .offset(x: geometry.size.width * scale.position(of: reference.value) - 1)
                }

                if let value {
                    // A knob in the accent with a white rim and a soft shadow, which reads on
                    // every theme — a rim in the system background drew a black ring on navy.
                    Circle()
                        .fill(.tint)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                        .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                        .frame(width: 18, height: 18)
                        .offset(x: max(0, geometry.size.width * scale.position(of: value) - 9))
                        .motion(.readoutSmooth, value: value)
                }
            }
            .frame(height: 18)
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

/// What the sensor is, how precise it is, and one thing to try (R-28).
struct ExplainerCard: View {
    let descriptor: ReadingDescriptor

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("What this is", systemImage: "info.circle", text: descriptor.explainer.what)
            section("How precise", systemImage: "scope", text: descriptor.explainer.precision)
            section("Try this", systemImage: "lightbulb", text: descriptor.explainer.tryThis)
        }
        .readoutCard()
    }

    private func section(_ title: String, systemImage: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: title, symbol: systemImage)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The one-line explanation that precedes any system permission prompt (R-54, R-55).
struct PermissionCard: View {
    let permission: SensorPermission
    let isDenied: Bool
    let action: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: permission.symbol)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: isWorking)
            Text(permission.why)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            if isDenied {
                Text("\(permission.title) is turned off for Readout in the Settings app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task {
                    isWorking = true
                    await action()
                    isWorking = false
                }
            } label: {
                if isWorking {
                    ProgressView()
                } else {
                    Text(isDenied ? "Open Settings" : "Allow \(permission.title)")
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking)
        }
        .readoutCard(padding: 20, alignment: .center)
        .transition(.blurReplace)
    }
}

/// Shown in place of a reading this iPhone cannot take at all (R-7).
struct UnavailableCard: View {
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "slash.circle")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("\(name.prefix(1).uppercased() + name.dropFirst()) isn't available on this iPhone.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .readoutCard(padding: 20, alignment: .center)
    }
}

/// Proximity monitoring blanks the screen, so it waits for a deliberate start (R-68).
struct ProximityStartCard: View {
    let descriptor: ReadingDescriptor
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: descriptor.symbol)
                .font(.system(size: 40))
                .foregroundStyle(.tint)
            Text("Running the proximity sensor switches the screen off while something covers it, so it only runs while you are testing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Start test", systemImage: "play.fill", action: onStart)
                .buttonStyle(.glassProminent)
        }
        .readoutCard(padding: 20, alignment: .center)
        .transition(.blurReplace)
    }
}
