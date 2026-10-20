import SwiftUI

/// One glass card on the home grid: symbol, name, a single live value and a sparkline (R-16).
///
/// A pure view — the grid hands it everything, so it never observes the hub itself.
struct ReadingTile: View {
    let descriptor: ReadingDescriptor
    let availability: ReadingAvailability
    let sample: SensorSample?
    let trail: [Double]
    let units: DisplayUnits
    var isDimmed = false

    /// The card grows with the text, so a long name at an accessibility size has somewhere
    /// to go instead of being cut in half (R-52).
    @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 118

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: descriptor.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
                Text(descriptor.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            value
                .frame(maxWidth: .infinity, alignment: .leading)

            Sparkline(values: trail)
                .frame(height: 22)
                .opacity(trail.count > 1 ? 1 : 0)
        }
        .padding(12)
        .frame(height: height, alignment: .top)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .opacity(isDimmed ? 0.45 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.name)
        .accessibilityValue(accessibilityValue)
    }

    @ViewBuilder
    private var value: some View {
        switch availability {
        case .needsPermission(let permission):
            TileState(symbol: permission.symbol, text: "Tap to allow")
        case .denied(let permission):
            TileState(symbol: permission.symbol, text: "Allow in Settings")
        case .unavailable:
            TileState(symbol: "slash.circle", text: "Not on this iPhone")
        case .live, .ready:
            if case .coordinates = descriptor.tile, let sample, sample.values.count >= 2 {
                coordinates(sample)
            } else if let sample, let formatted = formattedValue(sample) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatted.text)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !formatted.symbol.isEmpty {
                        Text(formatted.symbol)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if descriptor.activation == .onDemand {
                // The camera, microphone and proximity sensor never run just because the
                // grid is open (R-19).
                TileState(symbol: "hand.tap", text: "Tap to measure")
            } else {
                TileState(symbol: "ellipsis", text: "Waiting…")
            }
        }
    }

    /// Latitude over longitude. The pair does not fit a half-width tile on one line, and a
    /// coordinate cut off mid-digit tells the reader nothing (R-16).
    private func coordinates(_ sample: SensorSample) -> some View {
        let pair = ValueFormatting.coordinatePair(
            latitude: sample.values[0],
            longitude: sample.values[1],
            format: units.coordinates
        )
        return VStack(alignment: .leading, spacing: 1) {
            Text(pair.latitude)
            Text(pair.longitude)
        }
        .font(.system(.subheadline, design: .rounded, weight: .semibold))
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    /// The tile's single value: a channel, the magnitude of a three-axis reading, a discrete
    /// state, or a coordinate pair (R-17).
    private func formattedValue(_ sample: SensorSample) -> ValueFormatting.Formatted? {
        switch descriptor.tile {
        case .state:
            guard let state = sample.state else { return nil }
            return ValueFormatting.Formatted(text: state, symbol: "")
        case .coordinates:
            guard sample.values.count >= 2 else { return nil }
            return ValueFormatting.Formatted(
                text: ValueFormatting.coordinate(
                    latitude: sample.values[0],
                    longitude: sample.values[1],
                    format: units.coordinates
                ),
                symbol: ""
            )
        case .channel, .magnitude:
            guard let value = descriptor.summaryValue(sample) else { return nil }
            let prefix = descriptor.estimateNote == nil ? "" : "≈"
            let formatted = ValueFormatting.format(value, unit: descriptor.summaryUnit, units: units)
            return ValueFormatting.Formatted(text: prefix + formatted.text, symbol: formatted.symbol)
        }
    }

    private var accessibilityValue: String {
        switch availability {
        case .needsPermission: "Needs permission. Tap to allow."
        case .denied: "Permission refused. Allow in Settings."
        case .unavailable: "Not available on this iPhone."
        case .live, .ready:
            if let sample, let formatted = formattedValue(sample) {
                formatted.spoken
            } else {
                descriptor.activation == .onDemand ? "Tap to measure" : "Waiting for a reading"
            }
        }
    }
}

private struct TileState: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.caption)
            Text(text)
                .font(.subheadline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }
}

/// The small trailing line on a tile. Flat when every value is the same, so a steady
/// reading does not draw a misleading wiggle.
struct Sparkline: View {
    let values: [Double]

    @Environment(\.themeAccent) private var accent

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                guard values.count > 1 else { return }
                let lowest = values.min() ?? 0
                let highest = values.max() ?? 1
                let span = highest - lowest
                let step = geometry.size.width / Double(values.count - 1)
                for (index, value) in values.enumerated() {
                    let fraction = span > 0 ? (value - lowest) / span : 0.5
                    let point = CGPoint(
                        x: Double(index) * step,
                        y: geometry.size.height * (1 - fraction)
                    )
                    if index == 0 {
                        path.move(to: point)
                    } else {
                        path.addLine(to: point)
                    }
                }
            }
            .stroke(accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .accessibilityHidden(true)
    }
}
