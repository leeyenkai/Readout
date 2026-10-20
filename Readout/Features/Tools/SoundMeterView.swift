import SwiftUI

/// Current, peak and average dB with a live history chart and the 85 dB warning (R-34).
///
/// Audio never leaves memory: only the level is read (R-56).
struct SoundMeterView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.themeAccent) private var accent

    @State private var lease: SensorLease?
    @State private var isCalibrating = false

    private let descriptor = ReadingCatalog.descriptor(.soundLevel)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                    summary
                    ReadingChartPanel(descriptor: descriptor, units: settings.displayUnits)
                    if let comparisons = descriptor.comparisons {
                        ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
                    }
                    controls
                    Text("Readout reads the microphone's level only. No audio is recorded or saved, and the figure is an uncalibrated estimate.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .themedSurface()
        .navigationTitle("Sound meter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.soundLevel])
            }
        }
        .onAppear { syncActivation() }
        .onDisappear {
            hub.release(lease)
            lease = nil
        }
        .onChange(of: hub.availability(.soundLevel)) { _, _ in syncActivation() }
        .sheet(isPresented: $isCalibrating) {
            CalibrationSheet(target: .sound)
        }
    }

    /// Starts the microphone once the permission allows it, and never more than once. The card
    /// above only asks; this reacts to the answer. Activating from the card as well used to
    /// leave an unbalanced claim behind, so the microphone kept running — indicator and all —
    /// long after the user had walked away from the tool (R-19, R-64).
    private func syncActivation() {
        guard hub.availability(.soundLevel).isUsable else { return }
        guard lease == nil else { return }
        lease = hub.activate(.soundLevel)
    }


    /// Nothing is shown while another app holds the microphone: the last number stops being
    /// true the moment the engine stops, and a frozen reading is worse than none (P-2).
    private var interruption: String? { hub.stalledReason(.soundLevel) }

    private var current: Double? { interruption == nil ? hub.sample(.soundLevel)?.value(0) : nil }

    private var level: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(isLoud ? Color.orange : accent)
                .symbolEffect(.variableColor.iterative, isActive: current != nil)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(current.map { "≈" + ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .readoutValue(size: 64)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isLoud ? Color.orange : Color.primary)
                Text("dB")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if let interruption {
                Label(interruption, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLoud {
                Label("Long exposure at this level risks your hearing", systemImage: "ear.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            current.map { "About \(ValueFormatting.decimal($0, digits: 0)) decibels" }
                ?? (interruption.map { "Paused. \($0)" } ?? "No reading")
        )
    }

    /// Peak, average and quietest all come from the same history the chart draws, so Reset
    /// clears the three of them together and none can disagree with the others.
    private var summary: some View {
        HStack(spacing: 0) {
            let stats = hub.buffer(.soundLevel).stats(channel: 0)
            statistic("Peak", stats?.maximum)
            statistic("Average", stats?.mean)
            statistic("Quietest", stats?.minimum)
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func statistic(_ label: String, _ value: Double?) -> some View {
        let text = value.map { ValueFormatting.decimal($0, digits: 0) } ?? "—"
        return VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value == nil ? "\(label), no reading yet" : "\(label) \(text) decibels")
    }

    /// A wrapping row, so a third control and large Dynamic Type do not push each other off
    /// the screen (R-52).
    private var controls: some View {
        FlowRow(spacing: 10) {
            Button(settings.soundRespondsFast ? "Fast" : "Slow") {
                settings.soundRespondsFast.toggle()
            }
            .buttonStyle(.glass)
            .accessibilityLabel(settings.soundRespondsFast ? "Fast response. Tap for slow." : "Slow response. Tap for fast.")

            Button("Reset") {
                hub.resetStats(.soundLevel)
                hub.clearHistory(.soundLevel)
            }
            .buttonStyle(.glass)

            Button("Calibrate") { isCalibrating = true }
                .buttonStyle(.glass)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isLoud: Bool {
        (current ?? 0) >= 85
    }
}
