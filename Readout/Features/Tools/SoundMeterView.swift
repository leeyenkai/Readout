import SwiftUI

/// Current, peak and average dB with a live history chart and the 85 dB warning (R-34).
///
/// Audio never leaves memory: only the level is read (R-56).
struct SoundMeterView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings

    private let descriptor = ReadingCatalog.descriptor(.soundLevel)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch hub.availability(.soundLevel) {
                case .needsPermission(let permission):
                    PermissionCard(permission: permission, isDenied: false) {
                        await hub.permissions.request(permission)
                        hub.activate(.soundLevel)
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
        .navigationTitle("Sound meter")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hub.activate(.soundLevel) }
        .onDisappear { hub.deactivate(.soundLevel) }
    }

    private var current: Double? { hub.sample(.soundLevel)?.value(0) }

    private var level: some View {
        VStack(spacing: 6) {
            Image(systemName: "waveform")
                .font(.title)
                .foregroundStyle(isLoud ? Color.orange : Color.accentColor)
                .symbolEffect(.variableColor.iterative, isActive: current != nil)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(current.map { "≈" + ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isLoud ? Color.orange : Color.primary)
                Text("dB")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            if isLoud {
                Label("Long exposure at this level risks your hearing", systemImage: "ear.trianglebadge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(current.map { "About \(ValueFormatting.decimal($0, digits: 0)) decibels" } ?? "No reading")
    }

    private var summary: some View {
        HStack(spacing: 0) {
            statistic("Peak", hub.audio.peak)
            if let stats = hub.buffer(.soundLevel).stats(channel: 0) {
                statistic("Average", stats.mean)
                statistic("Quietest", stats.minimum)
            }
        }
        .padding(.vertical, 14)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func statistic(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(ValueFormatting.decimal(value, digits: 0))
                .font(.title3.weight(.medium))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(ValueFormatting.decimal(value, digits: 0)) decibels")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(settings.soundRespondsFast ? "Fast" : "Slow") {
                settings.soundRespondsFast.toggle()
            }
            .buttonStyle(.glass)

            Button("Reset") {
                hub.resetStats(.soundLevel)
                hub.clearHistory(.soundLevel)
            }
            .buttonStyle(.glass)
        }
        .font(.subheadline.weight(.medium))
    }

    private var isLoud: Bool {
        (current ?? 0) >= 85
    }
}
