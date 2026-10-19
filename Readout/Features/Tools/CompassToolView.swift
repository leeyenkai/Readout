import SwiftUI

/// Rotating dial with heading, a bearing you can lock, coordinates and altitude below (R-33).
struct CompassToolView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var lockedBearing: Double?
    @State private var leases: [SensorLease] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch hub.availability(.heading) {
                case .needsPermission(let permission):
                    PermissionCard(permission: permission, isDenied: false) {
                        await hub.permissions.request(permission)
                    }
                case .denied(let permission):
                    PermissionCard(permission: permission, isDenied: true) {
                        hub.permissions.openSettings()
                    }
                case .unavailable:
                    UnavailableCard(name: "compass")
                case .live, .ready:
                    dial
                    headingReadout
                    if let lockedBearing {
                        drift(from: lockedBearing)
                    }
                    controls
                    positionPanel
                    if isAccuracyPoor {
                        calibrationNote
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Compass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.heading])
            }
        }
        .onAppear {
            leases = [
                hub.activate(.heading, rate: .display),
                hub.activate(.coordinates),
                hub.activate(.gpsAltitude),
            ]
        }
        .onDisappear {
            leases.forEach(hub.release)
            leases = []
        }
        .sensoryFeedback(trigger: cardinalIndex) { _, _ in
            // A tap as the dial crosses N, E, S or W (R-51).
            settings.hapticsEnabled ? .selection : nil
        }
    }

    private var heading: Double? {
        hub.sample(.heading)?.value(0)
    }

    /// Changes only when the nearest cardinal point changes, which is what the haptic follows.
    private var cardinalIndex: Int {
        guard let heading else { return -1 }
        return Int((heading / 90).rounded()) % 4
    }

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(.quaternary, lineWidth: 1.5)

            CompassDial()
                .rotationEffect(.degrees(-(heading ?? 0)))
                .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.25), value: heading)

            if let lockedBearing {
                Rectangle()
                    .fill(Color.orange)
                    .frame(width: 2)
                    .rotationEffect(.degrees(lockedBearing - (heading ?? 0)))
                    .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.25), value: heading)
            }

            Triangle()
                .fill(Color.accentColor)
                .frame(width: 18, height: 14)
                .offset(y: -140)
        }
        .frame(height: 300)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var headingReadout: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(heading.map { ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("°")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(heading.map(ValueFormatting.cardinal) ?? "")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Text(hub.sample(.heading)?.note ?? (settings.usesTrueNorth ? "True north" : "Magnetic north"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heading.map { "Heading \(ValueFormatting.decimal($0, digits: 0)) degrees, \(ValueFormatting.cardinal($0))" } ?? "No heading")
    }

    private func drift(from bearing: Double) -> some View {
        let difference = ((heading ?? bearing) - bearing + 540).truncatingRemainder(dividingBy: 360) - 180
        return HStack {
            Label("Locked at \(ValueFormatting.decimal(bearing, digits: 0))°", systemImage: "lock")
                .font(.subheadline)
            Spacer()
            Text("\(difference > 0 ? "+" : "")\(ValueFormatting.decimal(difference, digits: 0))°")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(abs(difference) < 2 ? Color.green : Color.orange)
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(settings.usesTrueNorth ? "True north" : "Magnetic north") {
                settings.usesTrueNorth.toggle()
            }
            .buttonStyle(.glass)

            Button(lockedBearing == nil ? "Lock bearing" : "Unlock") {
                lockedBearing = lockedBearing == nil ? heading : nil
            }
            .buttonStyle(.glass)
            .disabled(heading == nil)
        }
        .font(.subheadline.weight(.medium))
    }

    private var positionPanel: some View {
        VStack(spacing: 8) {
            if let sample = hub.sample(.coordinates), sample.values.count >= 2 {
                Text(ValueFormatting.coordinate(
                    latitude: sample.values[0],
                    longitude: sample.values[1],
                    format: settings.coordinateFormat
                ))
                .font(.subheadline)
                .monospacedDigit()
            } else {
                Text("Waiting for a fix…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let altitude = hub.sample(.gpsAltitude)?.value(0) {
                let formatted = ValueFormatting.format(altitude, unit: .altitude, units: settings.displayUnits)
                Text("Altitude \(formatted.spoken)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    /// iOS puts up its own figure-of-eight prompt; this explains why the dial is wandering (R-69).
    private var calibrationNote: some View {
        Label(
            "Heading accuracy is poor. Move away from metal and magnets, or wave the phone in a figure of eight.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    private var isAccuracyPoor: Bool {
        let accuracy = hub.location.headingAccuracy
        return accuracy < 0 || accuracy > 15
    }
}

private struct CompassDial: View {
    var body: some View {
        ZStack {
            ForEach(0..<72) { index in
                let isCardinal = index % 18 == 0
                let isMajor = index % 9 == 0
                Rectangle()
                    .fill(isCardinal ? Color.primary : Color.secondary.opacity(isMajor ? 0.7 : 0.35))
                    .frame(width: isCardinal ? 2.5 : 1, height: isCardinal ? 18 : (isMajor ? 12 : 7))
                    .offset(y: -132)
                    .rotationEffect(.degrees(Double(index) * 5))
            }

            ForEach(Array(["N", "E", "S", "W"].enumerated()), id: \.offset) { index, letter in
                Text(letter)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(letter == "N" ? Color.red : Color.primary)
                    .offset(y: -104)
                    .rotationEffect(.degrees(Double(index) * 90))
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
