import SwiftUI

/// Rotating dial with heading, a bearing you can lock, coordinates and altitude below (R-33).
///
/// The compass needs no permission: the magnetometer is enough for magnetic north. Location
/// is asked for only to point at true north, and the dial carries on against magnetic north
/// while it is not allowed (SPEC §3, reading 5).
struct CompassToolView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder

    @State private var lockedBearing: Double?
    @State private var leases: [SensorLease] = []
    /// The heading with its turns kept: 350° then 10° is 370°, not a spin back through 180°.
    @State private var dialAngle: Double = 0

    var body: some View {
        ReadoutScreen {
            if hub.availability(.heading) == .unavailable {
                UnavailableCard(name: "compass")
            } else {
                dial
                headingReadout
                if let lockedBearing {
                    drift(from: lockedBearing)
                        .transition(.blurReplace.combined(with: .move(edge: .top)))
                }
                controls
                northPicker
                if isAccuracyPoor {
                    calibrationNote
                        .transition(.blurReplace)
                }
                positionPanel
            }
        }
        .motion(.readoutSnappy, value: lockedBearing == nil)
        .motion(.readoutSnappy, value: isAccuracyPoor)
        .navigationTitle("Compass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.heading])
            }
        }
        .onAppear {
            guard leases.isEmpty else { return }
            leases = [
                hub.activate(.heading, rate: .display),
                hub.activate(.coordinates),
                hub.activate(.gpsAltitude),
            ]
            dialAngle = heading ?? 0
        }
        .onDisappear {
            leases.forEach(hub.release)
            leases = []
        }
        .onChange(of: heading) { _, new in
            guard let new else { return }
            dialAngle = CompassMaths.unwrapped(previous: dialAngle, next: new)
        }
        .sensoryFeedback(trigger: cardinalCrossing) { _, crossing in
            // A tap as the dial crosses N, E, S or W, and only then (R-51).
            settings.hapticsEnabled && crossing != nil ? .selection : nil
        }
    }

    private var heading: Double? {
        hub.sample(.heading)?.value(0)
    }

    /// Which cardinal point the dial is sitting on, which is what the haptic follows (R-51).
    private var cardinalCrossing: Int? {
        heading.flatMap { CompassMaths.cardinalCrossing(heading: $0) }
    }

    /// Sized from the space it is given rather than from a fixed 300 points, so the dial
    /// still fits a small iPhone and still fills a large one.
    private var dial: some View {
        GeometryReader { geometry in
            let diameter = min(geometry.size.width, geometry.size.height)
            let radius = diameter / 2

            ZStack {
                Circle()
                    .fill(.white.opacity(0.03))
                Circle()
                    .stroke(.quaternary, lineWidth: 1.5)

                CompassDial(radius: radius, heading: dialAngle)
                    .rotationEffect(.degrees(-dialAngle))

                if let lockedBearing {
                    LockedBearing(radius: radius, offset: lockedBearing - dialAngle)
                        .transition(.opacity)
                }

                Triangle()
                    .fill(.tint)
                    .frame(width: 18, height: 14)
                    .offset(y: -(radius - 7))
            }
            .motion(.readoutFollow, value: dialAngle)
            .frame(width: diameter, height: diameter)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: 330)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }

    private var headingReadout: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(heading.map { ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .readoutValue(size: 56)
                    .monospacedDigit()
                Text("°")
                    .readoutValue(size: 36, weight: .regular)
                    .foregroundStyle(.secondary)
                Text(heading.map(ValueFormatting.cardinal) ?? "")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tint)
                    .padding(.leading, 4)
            }
            Text(northCaption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(heading.map { "Heading \(ValueFormatting.decimal($0, digits: 0)) degrees, \(ValueFormatting.cardinal($0))" } ?? "No heading")
    }

    /// Which north the number is measured from — and, in the Simulator, that it is simulated —
    /// rather than one replacing the other (P-2).
    private var northCaption: String {
        let note = hub.sample(.heading)?.note
        if note == "Simulated" {
            return "\(settings.usesTrueNorth ? "True north" : "Magnetic north") · Simulated"
        }
        return note ?? (settings.usesTrueNorth ? "True north" : "Magnetic north")
    }

    private func drift(from bearing: Double) -> some View {
        let difference = CompassMaths.drift(from: bearing, to: heading ?? bearing)
        return HStack {
            Label("Locked at \(ValueFormatting.decimal(bearing, digits: 0))°", systemImage: "lock.fill")
                .font(.subheadline.weight(.medium))
            Spacer()
            Text("\(difference > 0 ? "+" : "")\(ValueFormatting.decimal(difference, digits: 0))°")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(abs(difference) < 2 ? Color.green : Color.orange)
        }
        .readoutCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Locked at \(ValueFormatting.decimal(bearing, digits: 0)) degrees, \(ValueFormatting.decimal(abs(difference), digits: 0)) degrees \(difference > 0 ? "right" : "left") of it")
    }

    private var controls: some View {
        InstrumentControls {
            Button(lockedBearing == nil ? "Lock bearing" : "Unlock", systemImage: lockedBearing == nil ? "lock.fill" : "lock.open.fill") {
                lockedBearing = lockedBearing == nil ? heading.map(CompassMaths.normalised) : nil
            }
            .contentTransition(.symbolEffect(.replace))
            .disabled(heading == nil)
        }
    }

    /// True or magnetic, as a control that shows which one is on. True north needs Location;
    /// until it is allowed the dial reads magnetic north and says so.
    private var northPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("North", selection: Binding(
                get: { settings.usesTrueNorth },
                set: { settings.usesTrueNorth = $0 }
            )) {
                Text("True north").tag(true)
                Text("Magnetic north").tag(false)
            }
            .pickerStyle(.segmented)
            // A recording's heading column means one north from start to finish (R-45).
            .disabled(recorder.isRecording(.heading))

            if recorder.isRecording(.heading) {
                Text("Fixed while a recording is logging the heading.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if settings.usesTrueNorth {
                trueNorthPermission
            }
        }
    }

    /// Read from a location reading's availability rather than the permission itself, so the
    /// Simulator — where the permission gate is bypassed — does not offer a prompt that has
    /// nothing to do (R-71).
    @ViewBuilder
    private var trueNorthPermission: some View {
        switch hub.availability(.coordinates) {
        case .live, .ready, .unavailable:
            EmptyView()
        case .needsPermission:
            HStack {
                Text("True north needs your location. Until then this is magnetic north.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Allow") {
                    Task { await hub.requestPermission(.locationWhenInUse) }
                }
                .buttonStyle(.glassProminent)
                .font(.caption.weight(.semibold))
            }
        case .denied:
            HStack {
                Text("Location is off for Readout, so this is magnetic north.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Settings") { hub.permissions.openSettings() }
                    .buttonStyle(.glass)
                    .font(.caption.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var positionPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: "Position", symbol: "location.fill")
            switch hub.availability(.coordinates) {
            case .needsPermission, .denied:
                Text("Coordinates and altitude need your location.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            default:
                if let sample = hub.sample(.coordinates), sample.values.count >= 2 {
                    Text(ValueFormatting.coordinate(
                        latitude: sample.values[0],
                        longitude: sample.values[1],
                        format: settings.coordinateFormat
                    ))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                } else {
                    WaitingLabel(text: "Waiting for a position…")
                }
                if let altitude = hub.sample(.gpsAltitude)?.value(0), altitude.isFinite {
                    let formatted = ValueFormatting.format(altitude, unit: .altitude, units: settings.displayUnits)
                    Text("Altitude \(formatted.spoken)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .readoutCard()
    }

    /// iOS puts up its own figure-of-eight prompt; this explains why the dial is wandering (R-69).
    private var calibrationNote: some View {
        Label(
            "Heading accuracy is poor. Move away from metal and magnets, or wave the phone in a figure of eight.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .font(.footnote)
        .foregroundStyle(.orange)
        .readoutCard(padding: 14)
    }

    private var isAccuracyPoor: Bool {
        // The Simulator has no heading accuracy to report.
        guard hub.sample(.heading)?.note != "Simulated" else { return false }
        let accuracy = hub.location.headingAccuracy
        return accuracy < 0 || accuracy > 15
    }
}

private struct CompassDial: View {
    /// Half the dial's width, so the ticks and letters sit just inside its rim.
    let radius: Double
    /// The dial's own rotation, so its lettering can be turned back upright.
    let heading: Double

    var body: some View {
        ZStack {
            ForEach(0..<120) { index in
                let degrees = index * 3
                let isCardinal = degrees % 90 == 0
                let isMajor = degrees % 30 == 0
                Capsule()
                    .fill(isCardinal ? Color.primary : Color.secondary.opacity(isMajor ? 0.8 : 0.35))
                    .frame(width: isCardinal ? 3 : (isMajor ? 1.5 : 1), height: isCardinal ? 18 : (isMajor ? 12 : 6))
                    .offset(y: -(radius - 14))
                    .rotationEffect(.degrees(Double(degrees)))
            }

            // Every 30°, upright whichever way the dial has turned, as a real compass card
            // is printed — the four cardinal letters larger, north in red.
            ForEach(0..<12) { index in
                let degrees = index * 30
                let letter = ["N", "E", "S", "W"][safe: degrees / 90]
                Group {
                    if degrees % 90 == 0, let letter {
                        Text(letter)
                            .font(.system(size: radius * 0.13, weight: .bold, design: .rounded))
                            .foregroundStyle(letter == "N" ? Color.red : Color.primary)
                    } else {
                        Text("\(degrees)")
                            .font(.system(size: radius * 0.07, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .rotationEffect(.degrees(heading - Double(degrees)))
                .offset(y: -(radius - radius * 0.27))
                .rotationEffect(.degrees(Double(degrees)))
            }
        }
    }
}

/// The locked bearing: a line from the centre to the rim, drawn in when the bearing is
/// locked, and the arc between it and where the phone points now (R-33).
private struct LockedBearing: View {
    let radius: Double
    /// Where the bearing sits relative to the top of the dial, in degrees clockwise.
    let offset: Double

    @State private var isDrawn = false

    var body: some View {
        ZStack {
            DriftArc(radius: radius * 0.62, sweep: CompassMaths.drift(from: 0, to: CompassMaths.normalised(offset)))
                .stroke(Color.orange.opacity(0.45), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            BearingLine(length: radius - 24)
                .trim(from: 0, to: isDrawn ? 1 : 0)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(offset))
        }
        .onAppear {
            withReadoutAnimation(.readoutSmooth) { isDrawn = true }
        }
    }
}

/// From the centre straight up, `length` long.
private struct BearingLine: Shape {
    let length: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY - length))
        return path
    }
}

/// An arc from the top of the dial, `sweep` degrees clockwise (or anticlockwise if negative).
private struct DriftArc: Shape {
    let radius: Double
    let sweep: Double

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        path.addArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + sweep),
            clockwise: sweep < 0
        )
        return path
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

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
