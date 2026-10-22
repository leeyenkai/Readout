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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: descriptor.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
                    // The sound tile's waveform ripples while the microphone is live, faster
                    // the louder it is (R-48).
                    .symbolEffect(
                        .variableColor.iterative,
                        options: .repeating.speed(soundEffectSpeed),
                        isActive: soundEffectSpeed > 0 && !reduceMotion
                    )
                Text(descriptor.name)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }

            value
                .frame(maxWidth: .infinity, alignment: .leading)
                .motion(.readoutSnappy, value: stateKey)

            Sparkline(values: trail)
                .frame(height: 22)
                .opacity(trail.count > 1 ? 1 : 0)
                .motion(.readoutSmooth, value: trail.count > 1)
        }
        .padding(12)
        .frame(height: height, alignment: .top)
        .contentShape(.rect(cornerRadius: Metrics.tileRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.tileRadius))
        .opacity(isDimmed ? 0.45 : 1)
        .scaleEffect(isDimmed ? 0.97 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(descriptor.name)
        .accessibilityValue(accessibilityValue)
    }

    /// How fast the sound tile's symbol ripples: not at all unless the microphone is live, and
    /// quicker as the level rises from a quiet room towards a concert.
    private var soundEffectSpeed: Double {
        guard descriptor.id == .soundLevel, availability == .live, let level = sample?.value(0) else { return 0 }
        return 0.5 + SoundScale.fraction(of: level) * 2
    }

    /// Which kind of thing the tile is showing, so a change from one to another — waiting to
    /// a live value, needing permission to running — cross-fades rather than snapping.
    private var stateKey: Int {
        switch availability {
        case .needsPermission: 0
        case .denied: 1
        case .unavailable: 2
        case .live, .ready: sample == nil ? 3 : 4
        }
    }

    @ViewBuilder
    private var value: some View {
        Group {
            switch availability {
            case .needsPermission(let permission):
                TileState(symbol: permission.symbol, text: "Tap to allow")
            case .denied(let permission):
                TileState(symbol: permission.symbol, text: "Allow in Settings")
            case .unavailable:
                TileState(symbol: "slash.circle", text: "Not on this iPhone")
            case .live, .ready:
                liveValue
            }
        }
        .id(stateKey)
        .transition(.blurReplace)
    }

    @ViewBuilder
    private var liveValue: some View {
        if case .coordinates = descriptor.tile, let sample, sample.values.count >= 2 {
            coordinates(sample)
        } else if let sample, let formatted = formattedValue(sample) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatted.text)
                        .font(.system(.title2, design: .rounded, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        // Slow readings roll their digits as they change. Fast ones do not:
                        // digits rolling ten times a second read as noise, not polish.
                        .motion(.readoutSnappy, value: descriptor.updatesSlowly ? formatted.text : "")
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
            let line = path(in: geometry.size)
            ZStack {
                // A faint wash under the line gives it weight without competing with the
                // number above it.
                areaPath(line, in: geometry.size)
                    .fill(LinearGradient(
                        colors: [accent.opacity(0.22), accent.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    ))
                line
                    .stroke(accent.opacity(0.85), style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func path(in size: CGSize) -> Path {
        Path { path in
            guard values.count > 1 else { return }
            let lowest = values.min() ?? 0
            let highest = values.max() ?? 1
            let span = highest - lowest
            let step = size.width / Double(values.count - 1)
            for (index, value) in values.enumerated() {
                let fraction = span > 0 ? (value - lowest) / span : 0.5
                // A hair of inset top and bottom, so the stroke is not clipped at an extreme.
                let point = CGPoint(
                    x: Double(index) * step,
                    y: 1 + (size.height - 2) * (1 - fraction)
                )
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }

    private func areaPath(_ line: Path, in size: CGSize) -> Path {
        guard values.count > 1 else { return Path() }
        var area = line
        area.addLine(to: CGPoint(x: size.width, y: size.height))
        area.addLine(to: CGPoint(x: 0, y: size.height))
        area.closeSubpath()
        return area
    }
}
