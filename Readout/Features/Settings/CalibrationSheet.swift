import SwiftUI

/// Which of the two estimates is being calibrated (R-10, R-66).
enum CalibrationTarget: String, Identifiable, CaseIterable, Sendable {
    case sound, light

    var id: String { rawValue }

    var reading: ReadingID {
        switch self {
        case .sound: .soundLevel
        case .light: .light
        }
    }

    var title: String {
        switch self {
        case .sound: "Calibrate sound"
        case .light: "Calibrate light"
        }
    }

    /// The row that opens this sheet, in Settings and in the tool.
    static let buttonTitle = "Calibrate against a meter"

    var unitSymbol: String {
        switch self {
        case .sound: "dB"
        case .light: "lux"
        }
    }

    /// How to take the comparison, in a sentence or two. The instructions matter more than the
    /// arithmetic: a calibration taken with the two meters pointing at different things is
    /// worse than none at all.
    var instructions: String {
        switch self {
        case .sound:
            """
            Put Readout and a sound level meter side by side, facing the same steady source — \
            a fan or a running tap is easier to match than speech. Wait for both figures to \
            settle, then type the meter's reading here.
            """
        case .light:
            """
            Lay Readout face up beside a lux meter under even light, with nothing shadowing \
            either of them, and point the rear camera at the same surface the meter is \
            reading. Wait for the figure to settle, then type the meter's reading here.
            """
        }
    }

    /// What the correction is and where it is kept, so nobody takes it for a factory
    /// calibration (P-2, R-72).
    var footnote: String {
        switch self {
        case .sound:
            """
            Readout works sound out from the microphone's signal level, which no iOS API \
            relates to an absolute pressure, so the figure starts as an estimate. A \
            calibration shifts the whole scale by a fixed number of decibels; it is kept on \
            this iPhone and applies to the sound reading and the Sound meter.
            """
        case .light:
            """
            Readout works light out from the camera's exposure, which depends on the lens and \
            the sensor, so the figure starts as an estimate. A calibration multiplies it; it \
            is kept on this iPhone and applies to the Light reading and the Light meter. \
            The front and rear cameras differ, so calibrate with the one you use.
            """
        }
    }
}

/// Turns a reading taken with a reference meter into the user's own correction (R-10, R-66).
///
/// The sheet runs the sensor itself, through an ordinary lease, so it works the same from
/// Settings as it does from inside a tool (R-64).
struct CalibrationSheet: View {
    let target: CalibrationTarget

    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var lease: SensorLease?
    @State private var reference = ""
    @State private var outcome: Outcome?

    private enum Outcome: Equatable {
        case applied(String)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch hub.availability(target.reading) {
                case .needsPermission(let permission):
                    Section {
                        PermissionCard(permission: permission, isDenied: false) {
                            await hub.requestPermission(permission)
                        }
                        .listRowBackground(Color.clear)
                    }
                case .denied(let permission):
                    Section {
                        PermissionCard(permission: permission, isDenied: true) {
                            hub.permissions.openSettings()
                        }
                        .listRowBackground(Color.clear)
                    }
                case .unavailable:
                    Section {
                        UnavailableCard(name: target == .sound ? "microphone" : "camera")
                            .listRowBackground(Color.clear)
                    }
                case .live, .ready:
                    measurement
                    entry
                    correction
                }
            }
            .navigationTitle(target.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { lease = hub.activate(target.reading) }
            .onDisappear {
                hub.release(lease)
                lease = nil
            }
        }
    }

    // MARK: - Sections

    private var measurement: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(measured.map { "≈" + ValueFormatting.decimal($0, digits: digits) } ?? "—")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(target.unitSymbol)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                measured.map { "Readout reads about \(ValueFormatting.decimal($0, digits: digits)) \(target.unitSymbol)" }
                    ?? "Waiting for a reading"
            )

            if let stalled = hub.stalledReason(target.reading) {
                Label(stalled, systemImage: "pause.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if measured != nil {
                Text("Averaged over the last \(Int(Self.averagingWindow)) seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        } header: {
            Text("Readout reads")
        } footer: {
            Text(target.instructions)
        }
    }

    private var entry: some View {
        Section {
            HStack {
                Text("Reference meter")
                Spacer()
                TextField("0", text: $reference)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    .frame(maxWidth: 110)
                Text(target.unitSymbol)
                    .foregroundStyle(.secondary)
            }

            Button("Apply", action: apply)
                .disabled(!canApply)

            switch outcome {
            case .applied(let message):
                Label(message, systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            case nil:
                EmptyView()
            }
        } header: {
            Text("The meter reads")
        }
    }

    private var correction: some View {
        Section {
            LabeledContent("Your correction", value: currentCorrectionText)
            Button("Clear", action: clear)
                .disabled(!hasCorrection)
        } footer: {
            Text(target.footnote)
        }
    }

    // MARK: - State

    /// The figure the correction is worked out from: a mean of the last few seconds rather
    /// than whatever the number happened to be at the instant Apply was tapped. A level meter
    /// twitches, and a calibration taken off one twitch calibrates the twitch.
    private var measured: Double? {
        guard hub.stalledReason(target.reading) == nil else { return nil }
        let values = hub.buffer(target.reading)
            .samples(in: Self.averagingWindow)
            .compactMap { $0.value(0) }
            .filter(\.isFinite)
        guard !values.isEmpty else { return hub.sample(target.reading)?.value(0) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Long enough to average out a flicker, short enough that moving the phone and trying
    /// again does not mean waiting.
    private static let averagingWindow: TimeInterval = 5

    /// Decibels are worth a decimal place while matching a meter; lux is never that precise.
    private var digits: Int { target == .sound ? 1 : 0 }

    private var canApply: Bool {
        measured != nil && Calibration.parse(reference) != nil
    }

    private var hasCorrection: Bool {
        switch target {
        case .sound: settings.soundCalibrationOffset != 0
        case .light: settings.lightCalibration != 1
        }
    }

    private var currentCorrectionText: String {
        switch target {
        case .sound:
            let offset = settings.soundCalibrationOffset
            guard offset != 0 else { return "None" }
            return "\(offset > 0 ? "+" : "")\(ValueFormatting.decimal(offset, digits: 1)) dB"
        case .light:
            let multiplier = settings.lightCalibration
            guard multiplier != 1 else { return "None" }
            return "× \(ValueFormatting.decimal(multiplier, digits: 2))"
        }
    }

    // MARK: - Actions

    private func apply() {
        guard let measured, let reference = Calibration.parse(reference) else { return }
        switch target {
        case .sound:
            let result = Calibration.soundOffset(
                measured: measured,
                reference: reference,
                currentOffset: settings.soundCalibrationOffset
            )
            switch result {
            case .success(let offset):
                settings.soundCalibrationOffset = offset
                outcome = .applied("Sound now reads \(offset > 0 ? "+" : "")\(ValueFormatting.decimal(offset, digits: 1)) dB against the microphone's own level.")
            case .failure(let failure):
                outcome = .failed(message(for: failure))
            }
        case .light:
            let result = Calibration.lightMultiplier(
                measured: measured,
                reference: reference,
                currentMultiplier: settings.lightCalibration
            )
            switch result {
            case .success(let multiplier):
                settings.lightCalibration = multiplier
                outcome = .applied("Light now reads × \(ValueFormatting.decimal(multiplier, digits: 2)) of the camera's own estimate.")
            case .failure(let failure):
                outcome = .failed(message(for: failure))
            }
        }
    }

    private func clear() {
        switch target {
        case .sound: settings.soundCalibrationOffset = 0
        case .light: settings.lightCalibration = 1
        }
        reference = ""
        outcome = nil
    }

    private func message(for failure: Calibration.Failure) -> String {
        switch failure {
        case .notAReading:
            "That is not a reading Readout can match. Type the figure the meter shows."
        case .tooFarApart:
            switch target {
            case .sound:
                "That is more than \(ValueFormatting.decimal(Calibration.soundOffsetRange.upperBound, digits: 0)) dB from what Readout reads, which is too far to be a calibration. Check that both meters are measuring the same source."
            case .light:
                "That is further from Readout's estimate than a calibration can account for. Check that the camera and the meter are reading the same surface."
            }
        }
    }
}
