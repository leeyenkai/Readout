import SwiftUI

/// Minimum, maximum and mean since the view opened, with a reset (R-26).
struct StatsPanel: View {
    let descriptor: ReadingDescriptor
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Since you opened this")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    hub.resetStats(descriptor.id)
                }
                .font(.footnote.weight(.semibold))
            }

            ForEach(Array(descriptor.channels.enumerated()), id: \.offset) { index, channel in
                if let stats = hub.buffer(descriptor.id).stats(channel: index) {
                    HStack(spacing: 0) {
                        if descriptor.channels.count > 1 {
                            Text(channel.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(channel.axis?.colour ?? .secondary)
                                .frame(width: 54, alignment: .leading)
                        }
                        statistic("Min", stats.minimum, channel: channel)
                        statistic("Max", stats.maximum, channel: channel)
                        statistic("Avg", stats.mean, channel: channel)
                    }
                }
            }
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func statistic(_ label: String, _ value: Double, channel: ReadingChannel) -> some View {
        let formatted = ValueFormatting.format(value, unit: channel.unit, units: units)
        return VStack(spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(formatted.text)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(formatted.spoken)")
    }
}

/// The current value placed on a bar of everyday references (R-27).
struct ComparisonPanel: View {
    let descriptor: ReadingDescriptor
    let scale: ComparisonScale
    let units: DisplayUnits

    @Environment(SensorHub.self) private var hub

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How that compares")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)

            ComparisonBar(scale: scale, value: currentValue)

            if let nearest = currentValue.flatMap(scale.nearest(to:)) {
                Text("About the same as \(nearest.label.lowercased())")
                    .font(.subheadline)
                    .foregroundStyle(nearest.caution ? .orange : .secondary)
            }

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
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private var unit: ValueUnit {
        descriptor.channels.first?.unit ?? .none
    }

    private var currentValue: Double? {
        hub.sample(descriptor.id).flatMap(descriptor.summaryValue)
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
                    .frame(height: 10)

                ForEach(scale.references) { reference in
                    Capsule()
                        .fill(reference.caution ? Color.orange.opacity(0.8) : Color.secondary.opacity(0.5))
                        .frame(width: 2, height: 16)
                        .offset(x: geometry.size.width * scale.position(of: reference.value) - 1)
                }

                if let value {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.background, lineWidth: 2))
                        .offset(x: max(0, geometry.size.width * scale.position(of: value) - 8))
                        .animation(.smooth(duration: 0.25), value: value)
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
        VStack(alignment: .leading, spacing: 12) {
            label("What this is", systemImage: "info.circle")
            Text(descriptor.explainer.what)
                .font(.subheadline)

            label("How precise", systemImage: "scope")
            Text(descriptor.explainer.precision)
                .font(.subheadline)

            label("Try this", systemImage: "lightbulb")
            Text(descriptor.explainer.tryThis)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }

    private func label(_ text: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.caption)
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.secondary)
        .padding(.top, 2)
    }
}

/// The one-line explanation that precedes any system permission prompt (R-54, R-55).
struct PermissionCard: View {
    let permission: SensorPermission
    let isDenied: Bool
    let action: () async -> Void

    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: permission.symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text(permission.why)
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button(isDenied ? "Open Settings" : "Allow \(permission.title)") {
                Task {
                    isWorking = true
                    await action()
                    isWorking = false
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isWorking)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

struct UnavailableCard: View {
    let name: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "slash.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("This iPhone has no \(name.lowercased()) sensor.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// Proximity monitoring blanks the screen, so it waits for a deliberate start (R-68).
struct ProximityStartCard: View {
    let descriptor: ReadingDescriptor
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: descriptor.symbol)
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("Running the proximity sensor switches the screen off while something covers it, so it only runs while you are testing.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
            Button("Start test", action: onStart)
                .buttonStyle(.glassProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

/// A plain wrapping row, for the comparison chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > width, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? rowWidth, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
