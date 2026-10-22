import SwiftUI

/// The phone in 3D: a model that turns as the real phone does, from Core Motion's attitude,
/// and sways as it is pushed (R-86).
struct AttitudeToolView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Made once, here. `@State` keeps the instance for the life of the screen, and its
    /// initialiser builds nothing, so the throwaway copies SwiftUI makes cost nothing.
    @State private var stage = PhoneStage()
    @State private var leases: [SensorLease] = []
    @State private var held: SensorSample?
    @State private var recentred = 0

    var body: some View {
        ReadoutScreen {
            if hub.availability(.orientation) == .unavailable {
                UnavailableCard(name: "the motion sensor")
            } else {
                stageCard
                readout
                controls
                explainer
            }
        }
        .navigationTitle("Attitude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.orientation, .acceleration, .rotationRate])
            }
        }
        .onAppear {
            stage.attach(hub)
            stage.showsGuides = settings.attitudeShowsAxes
            stage.sways = settings.attitudeSways
            stage.recentre()
            guard leases.isEmpty else { return }
            // Both at display rate: they share Core Motion's one stream, and the attitude and
            // the push have to arrive together for the sway to match the turn.
            leases = [
                hub.activate(.orientation, rate: .display),
                hub.activate(.acceleration, rate: .display),
            ]
        }
        .onDisappear {
            leases.forEach(hub.release)
            leases = []
            stage.detach()
        }
        .onChange(of: reduceMotion, initial: true) { _, reduce in
            stage.reduceMotion = reduce
        }
        .sensoryFeedback(trigger: recentred) { _, _ in
            settings.hapticsEnabled ? .impact(weight: .light) : nil
        }
    }

    private var isHeld: Bool { held != nil }

    private var stageCard: some View {
        ZStack {
            // A pool of the accent behind the phone and a soft shadow under it, so the model
            // sits in a space rather than floating on black.
            StageGlow()
            AttitudeStage(stage: stage)
        }
        .frame(height: 380)
        .clipShape(.rect(cornerRadius: Metrics.cardRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
        .overlay(alignment: .topLeading) {
            if isHeld {
                StatusBadge(text: "Held", symbol: "pause.fill")
                    .padding(12)
            }
        }
        .overlay(alignment: .bottom) {
            Text("Drag to look around")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
        .motion(.readoutSnappy, value: isHeld)
    }

    /// Pitch, roll and yaw in their axis colours — the same three the guides on the model are
    /// drawn in — and how hard the phone is being pushed.
    private var readout: some View {
        let sample = held ?? hub.sample(.orientation)
        let push = hub.userAcceleration.map(\.magnitude)
        let units = settings.displayUnits
        return VStack(spacing: 12) {
            HStack(spacing: 0) {
                angle("Pitch", sample?.value(0), axis: .x)
                angle("Roll", sample?.value(1), axis: .y)
                angle("Yaw", sample?.value(2), axis: .z)
            }
            Divider()
            HStack {
                Label("Push", systemImage: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(isHeld ? "—" : push.map { ValueFormatting.format($0, unit: .acceleration, units: units).spoken } ?? "—")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .accessibilityElement(children: .combine)
        }
        .readoutCard(padding: 16)
    }

    private func angle(_ name: String, _ value: Double?, axis: Axis) -> some View {
        VStack(spacing: 2) {
            Text(name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(axis.colour)
            Text(value.map { "\(ValueFormatting.decimal($0, digits: 0))°" } ?? "—")
                .readoutValue(size: 30)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name) \(value.map { ValueFormatting.decimal($0, digits: 0) } ?? "unknown") degrees")
    }

    private var controls: some View {
        VStack(spacing: 12) {
            InstrumentControls {
                Button(isHeld ? "Release" : "Hold", systemImage: isHeld ? "play.fill" : "pause.fill") {
                    withReadoutAnimation {
                        held = isHeld ? nil : hub.sample(.orientation)
                    }
                    stage.isHeld = held != nil
                }
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHint(isHeld ? "Lets the model follow the phone again" : "Freezes the model where it is")

                Button("Recentre", systemImage: "scope") {
                    stage.recentre()
                    recentred += 1
                }
                .disabled(isHeld)
                .accessibilityHint("Turns the model to face the way you are holding the phone")
            }

            VStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { settings.attitudeShowsAxes },
                    set: { show in
                        settings.attitudeShowsAxes = show
                        stage.showsGuides = show
                    }
                )) {
                    Label("Show the three axes", systemImage: "move.3d")
                }
                Divider()
                Toggle(isOn: Binding(
                    get: { settings.attitudeSways },
                    set: { sways in
                        settings.attitudeSways = sways
                        stage.sways = sways
                    }
                )) {
                    Label("Sway when pushed", systemImage: "wave.3.right")
                }
                .disabled(reduceMotion)
            }
            .font(.subheadline.weight(.medium))
            .readoutCard(padding: 14)

            if reduceMotion {
                Text("Reduce Motion is on, so the model follows the phone without swaying.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 14) {
            section(
                "What this is",
                symbol: "info.circle",
                text: "Your phone's attitude — which way it faces — from Core Motion, which blends the gyroscope, accelerometer and magnetometer. The model turns as the phone does; the red, green and blue lines are the x, y and z axes the other motion readings are measured along."
            )
            section(
                "Why it sways rather than moves",
                symbol: "wave.3.right",
                text: "A phone cannot tell where it is from its accelerometer: working position out from acceleration turns a tiny sensor error into metres of imaginary travel within seconds. So a push makes the model sway on a spring, the way you moved it, and it always settles back to the middle. The arrow shows the push itself."
            )
            section(
                "Try this",
                symbol: "lightbulb",
                text: "Hold the phone upright and tap Recentre, then turn on the spot: the model turns with you. Give the phone a quick push sideways and watch it sway."
            )
        }
        .readoutCard()
    }

    private func section(_ title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: title, symbol: symbol)
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The light behind the phone: a soft pool of the theme's accent, and a floor shadow.
private struct StageGlow: View {
    @Environment(\.themeAccent) private var accent

    var body: some View {
        ZStack {
            RadialGradient(
                colors: [accent.opacity(0.28), accent.opacity(0.06), .clear],
                center: UnitPoint(x: 0.5, y: 0.42),
                startRadius: 10,
                endRadius: 220
            )
            Ellipse()
                .fill(RadialGradient(colors: [.black.opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 90))
                .frame(width: 200, height: 34)
                .offset(y: 150)
                .blur(radius: 6)
        }
        .allowsHitTesting(false)
    }
}
