import SwiftUI

/// Current, peak and average dB with a level bar, a live history chart and the 85 dB warning
/// (R-34).
///
/// Audio never leaves memory: only the level is read (R-56).
struct SoundMeterView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder

    @State private var lease: SensorLease?
    /// Leases are only ever taken while this is on screen. A tab switch hides the view without
    /// destroying it, and giving the lease back changes the availability this reacts to — so
    /// without the flag, leaving would open the microphone again behind the user's back (R-64).
    @State private var isVisible = false
    @State private var isCalibrating = false
    @State private var frozen: Double?

    private let descriptor = ReadingCatalog.descriptor(.soundLevel)

    var body: some View {
        ReadoutScreen {
            switch hub.availability(.soundLevel) {
            case .needsPermission(let permission):
                PermissionCard(permission: permission, isDenied: false) {
                    await hub.requestPermission(permission)
                }
            case .denied(let permission):
                PermissionCard(permission: permission, isDenied: true) {
                    hub.permissions.openSettings()
                }
            case .unavailable:
                UnavailableCard(name: "microphone")
            case .live, .ready:
                level
                controls
                summary
                ReadingChartPanel(descriptor: descriptor, units: settings.displayUnits)
                if let comparisons = descriptor.comparisons {
                    ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
                }
                Text("Readout reads the microphone's level only. No audio is recorded or saved, and the figure is an estimate rather than a calibrated measurement.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Sound meter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.soundLevel])
            }
        }
        .onAppear {
            isVisible = true
            syncActivation()
        }
        .onDisappear {
            isVisible = false
            hub.release(lease)
            lease = nil
        }
        .onChange(of: hub.availability(.soundLevel).isUsable) { _, _ in syncActivation() }
        .sheet(isPresented: $isCalibrating) {
            CalibrationSheet(target: .sound)
        }
    }

    /// Starts the microphone once the permission allows it, and never more than once. The card
    /// above only asks; this reacts to the answer. Activating from the card as well used to
    /// leave an unbalanced claim behind, so the microphone kept running — indicator and all —
    /// long after the user had walked away from the tool (R-19, R-64).
    private func syncActivation() {
        guard isVisible, hub.availability(.soundLevel).isUsable else { return }
        guard lease == nil else { return }
        lease = hub.activate(.soundLevel)
        // "Since you opened this" means since now, not since the microphone last ran.
        hub.resetStats(.soundLevel)
    }

    /// Nothing is shown while another app holds the microphone: the last number stops being
    /// true the moment the engine stops, and a frozen reading is worse than none (P-2).
    private var interruption: String? { hub.stalledReason(.soundLevel) }

    private var live: Double? { interruption == nil ? hub.sample(.soundLevel)?.value(0) : nil }

    /// What is on screen: the held figure if Hold is on.
    private var current: Double? { frozen ?? live }

    private var isLoud: Bool { (current ?? 0) >= 85 }

    private var level: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                // The symbol fills with the level, so the card reads at a glance (R-48).
                Image(systemName: "speaker.wave.3.fill", variableValue: SoundScale.fraction(of: current ?? 0))
                    .font(.title2)
                    .foregroundStyle(isLoud ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.automatic))
                if frozen != nil {
                    StatusBadge(text: "Held", symbol: "pause.fill")
                }
            }
            .motion(.readoutSnappy, value: frozen != nil)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(current.map { "≈" + ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .readoutValue(size: 68)
                    .monospacedDigit()
                    .foregroundStyle(isLoud ? Color.orange : Color.primary)
                Text("dB")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            LevelBar(value: current, isHeld: frozen != nil)
                .padding(.horizontal, 4)

            Group {
                if let interruption {
                    Label(interruption, systemImage: "pause.circle")
                        .foregroundStyle(.secondary)
                } else if isLoud {
                    Label("Long exposure at this level risks your hearing", systemImage: "ear.trianglebadge.exclamationmark")
                        .foregroundStyle(.orange)
                } else {
                    Text("Microphone estimate")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote)
            .transition(.blurReplace)
        }
        .motion(.readoutSnappy, value: isLoud)
        .motion(.readoutSnappy, value: interruption)
        .readoutCard(padding: 20, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            current.map { "About \(ValueFormatting.decimal($0, digits: 0)) decibels\(frozen != nil ? ", held" : "")" }
                ?? (interruption.map { "Paused. \($0)" } ?? "No reading")
        )
    }

    /// Peak, average and quietest, from the same history the chart draws, since the meter
    /// was opened or last reset.
    private var summary: some View {
        let stats = hub.buffer(.soundLevel).stats(channel: 0)
        return VStack(spacing: 10) {
            CardHeader(title: "Since you opened this") {
                Button("Reset") {
                    withReadoutAnimation { hub.resetStats(.soundLevel) }
                }
                .font(.footnote.weight(.semibold))
            }
            HStack(spacing: 0) {
                statistic("Quietest", stats?.minimum)
                statistic("Average", stats?.mean)
                statistic("Peak", stats?.maximum)
            }
        }
        .readoutCard(padding: 14)
    }

    private func statistic(_ label: String, _ value: Double?) -> some View {
        let text = value.map { ValueFormatting.decimal($0, digits: 0) } ?? "—"
        return StatColumn(
            label: label,
            text: value == nil ? text : "\(text) dB",
            spoken: value == nil ? "no reading yet" : "\(text) decibels"
        )
    }

    private var controls: some View {
        VStack(spacing: 12) {
            InstrumentControls {
                Button(frozen == nil ? "Hold" : "Release", systemImage: frozen == nil ? "pause.fill" : "play.fill") {
                    withReadoutAnimation {
                        frozen = frozen == nil ? live : nil
                    }
                }
                .contentTransition(.symbolEffect(.replace))
                .disabled(frozen == nil && live == nil)
                .accessibilityHint(frozen == nil ? "Freezes the reading" : "Lets the reading follow the microphone again")

                Button("Calibrate", systemImage: "slider.horizontal.3") { isCalibrating = true }
                    .disabled(isRecordingSound)
            }

            Picker("Response", selection: Binding(
                get: { settings.soundRespondsFast },
                set: { settings.soundRespondsFast = $0 }
            )) {
                Text("Fast response").tag(true)
                Text("Slow response").tag(false)
            }
            .pickerStyle(.segmented)
            .disabled(isRecordingSound)

            if isRecordingSound {
                // A recording's sound column means one calibration and one response from
                // start to finish (R-45).
                Text("Response and calibration are fixed while a recording is logging sound.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isRecordingSound: Bool { recorder.isRecording(.soundLevel) }
}

/// Where a level sits on the meter's bar, which runs from a quiet room to a concert.
enum SoundScale {
    static let floor = 30.0
    static let ceiling = 110.0
    static let caution = 85.0

    static func fraction(of decibels: Double) -> Double {
        guard decibels.isFinite else { return 0 }
        return ((decibels - floor) / (ceiling - floor)).clamped(to: 0...1)
    }
}

/// A horizontal level bar: the accent up to 85 dB, orange beyond, with a peak tick that holds
/// for a moment and then falls back, as a studio meter's does.
private struct LevelBar: View {
    let value: Double?
    let isHeld: Bool

    @Environment(\.themeAccent) private var accent
    @State private var peak: Double = SoundScale.floor
    @State private var peakTime = Date.distantPast

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = SoundScale.fraction(of: value ?? SoundScale.floor)
            let caution = SoundScale.fraction(of: SoundScale.caution)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(
                        stops: [
                            .init(color: accent.opacity(0.7), location: 0),
                            .init(color: accent, location: caution * 0.9),
                            .init(color: .orange, location: caution),
                            .init(color: .orange, location: 1),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    // The full-width gradient, revealed up to the level, so the colour at the
                    // tip is the colour of that level rather than a squashed copy of the scale.
                    .mask(alignment: .leading) {
                        Capsule().frame(width: max(8, width * fraction))
                    }
                    .motion(.readoutFollow, value: fraction)
                Rectangle()
                    .fill(Color.orange.opacity(0.6))
                    .frame(width: 1.5, height: 16)
                    .offset(x: width * caution)
                Capsule()
                    .fill(.primary)
                    .frame(width: 3, height: 16)
                    .offset(x: max(0, width * SoundScale.fraction(of: peak) - 1.5))
                    .opacity(peak > SoundScale.floor ? 0.9 : 0)
                    .motion(.readoutSmooth, value: peak)
            }
        }
        .frame(height: 12)
        .onChange(of: value) { _, new in
            guard let new, !isHeld else { return }
            let now = Date.now
            if new >= peak {
                peak = new
                peakTime = now
            } else if now.timeIntervalSince(peakTime) > 1.5 {
                // After a moment's hold the tick falls back towards the level.
                peak = max(new, peak - 1.5)
            }
        }
        .accessibilityHidden(true)
    }
}
