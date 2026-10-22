import SwiftUI

/// Units, appearance, recording, compass, calibration, haptics, hidden tiles, Privacy and
/// About (R-23).
struct SettingsView: View {
    /// Set when the user asks to see the welcome screen again. The readings screen shows it
    /// once this sheet has finished going away.
    @Binding var showsWelcomeAgain: Bool

    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder
    @Environment(\.dismiss) private var dismiss
    @State private var calibrating: CalibrationTarget?
    @State private var isConfirmingMaps = false
    @State private var isConfirmingClearCalibration = false

    var body: some View {
        NavigationStack {
            Form {
                units
                appearance
                recording
                compass
                calibration
                feedback
                hiddenReadings
                privacy
                about
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $calibrating) { target in
                CalibrationSheet(target: target)
            }
            .appleMapsConsent(isPresented: $isConfirmingMaps)
            .confirmationDialog(
                "Clear both calibrations?",
                isPresented: $isConfirmingClearCalibration,
                titleVisibility: .visible
            ) {
                Button("Clear calibration", role: .destructive) {
                    withReadoutAnimation { settings.resetCalibration() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Sound and light go back to their uncorrected estimates.")
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .themedSurface()
        }
    }

    private var units: some View {
        Section {
            Picker("Measurements", selection: Binding(
                get: { settings.unitSystem },
                set: { settings.unitSystem = $0 }
            )) {
                ForEach(UnitSystem.allCases) { system in
                    Text(system.title).tag(system)
                }
            }
            Picker("Acceleration", selection: Binding(
                get: { settings.accelerationUnit },
                set: { settings.accelerationUnit = $0 }
            )) {
                ForEach(AccelerationUnit.allCases) { unit in
                    Text(unit.title).tag(unit)
                }
            }
            Picker("Coordinates", selection: Binding(
                get: { settings.coordinateFormat },
                set: { settings.coordinateFormat = $0 }
            )) {
                ForEach(CoordinateFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
        } header: {
            Text("Units")
        } footer: {
            Text("Automatic follows your phone's region.")
        }
        .themedRows()
    }

    private var appearance: some View {
        Section {
            NavigationLink {
                AppearanceView()
            } label: {
                LabeledContent("Theme & size") {
                    Text("\(settings.theme.name) · \(settings.interfaceScale.title)")
                        .lineLimit(1)
                }
            }
        } header: {
            Text("Appearance")
        }
        .themedRows()
    }

    private var recording: some View {
        Section {
            Picker("Recording limit", selection: Binding(
                get: { settings.recordingLimit },
                set: { settings.recordingLimit = $0 }
            )) {
                ForEach(RecordingLimit.allCases) { limit in
                    Text(limit.title).tag(limit)
                }
            }
        } header: {
            Text("Recording")
        } footer: {
            Text("""
                \(settings.recordingLimit.detail) A recording already running keeps the limit \
                it started with. A recording that logs your position carries on when you leave \
                Readout; any other stops and keeps what it has.
                """)
        }
        .themedRows()
    }

    private var compass: some View {
        Section {
            Toggle("Point at true north", isOn: Binding(
                get: { settings.usesTrueNorth },
                set: { settings.usesTrueNorth = $0 }
            ))
            // A recording's heading means one north from start to finish (R-45).
            .disabled(recorder.isRecording(.heading))
        } header: {
            Text("Compass")
        } footer: {
            Text(recorder.isRecording(.heading)
                 ? "Fixed while a recording is logging the heading."
                 : "True north needs your location. Magnetic north is what the magnetometer sees.")
        }
        .themedRows()
    }

    private var calibration: some View {
        Section {
            LabeledContent("Sound offset") {
                Text("\(settings.soundCalibrationOffset, format: .number.precision(.fractionLength(1))) dB")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { settings.soundCalibrationOffset },
                    set: { settings.soundCalibrationOffset = $0 }
                ),
                in: Calibration.soundOffsetRange,
                step: 0.5
            )
            .accessibilityLabel("Sound offset in decibels")
            .disabled(recorder.isRecording(.soundLevel))
            Button("Calibrate sound against a meter…") { calibrating = .sound }
                .disabled(recorder.isRecording(.soundLevel))

            LabeledContent("Light multiplier") {
                Text(settings.lightCalibration, format: .number.precision(.fractionLength(2)))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Slider(
                value: Binding(
                    get: { settings.lightCalibration },
                    set: { settings.lightCalibration = $0 }
                ),
                in: Calibration.lightMultiplierRange,
                step: 0.05
            )
            .accessibilityLabel("Light multiplier")
            .disabled(recorder.isRecording(.light))
            Button("Calibrate light against a meter…") { calibrating = .light }
                .disabled(recorder.isRecording(.light))

            if settings.hasCalibration {
                Button("Clear calibration", role: .destructive) {
                    isConfirmingClearCalibration = true
                }
                .disabled(recorder.isRecording(.soundLevel) || recorder.isRecording(.light))
            }
        } header: {
            Text("Calibration")
        } footer: {
            Text("""
                Sound and light are estimates. Nudge them by hand, or hold a reference meter \
                beside the phone and let Readout work the correction out. \(Self.baselineNote)
                """)
        }
        .themedRows()
    }

    private var feedback: some View {
        Section {
            Toggle("Haptics", isOn: Binding(
                get: { settings.hapticsEnabled },
                set: { settings.hapticsEnabled = $0 }
            ))
        } header: {
            Text("Feedback")
        } footer: {
            Text("A tap when the level reaches 0°, when the compass crosses a cardinal point, and as a recording starts and stops.")
        }
        .themedRows()
    }

    @ViewBuilder
    private var hiddenReadings: some View {
        if !settings.hiddenReadings.isEmpty {
            Section("Hidden readings") {
                ForEach(settings.hiddenReadings.map(ReadingCatalog.descriptor).sorted { $0.name < $1.name }) { descriptor in
                    HStack {
                        Label(descriptor.name, systemImage: descriptor.symbol)
                        Spacer()
                        Button("Show") {
                            withReadoutAnimation { settings.setHidden(false, for: descriptor.id) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
            .themedRows()
        }
    }

    private var privacy: some View {
        Section {
            LabeledContent("Data collected", value: "None")
            LabeledContent("Network requests") {
                Text(settings.usesAppleMaps ? "Apple Maps only" : "None")
                    .contentTransition(.opacity)
            }
            Toggle("Show routes on Apple Maps", isOn: Binding(
                get: { settings.usesAppleMaps },
                set: { isOn in
                    // Turning it on asks first, as the route panel does; turning it off never
                    // needs asking.
                    if isOn {
                        isConfirmingMaps = true
                    } else {
                        withReadoutAnimation { settings.usesAppleMaps = false }
                    }
                }
            ))
        } header: {
            Text("Privacy")
        } footer: {
            Text("""
                Everything is measured and kept on this iPhone: no accounts, no analytics, and \
                microphone audio and camera frames are never saved. Routes are plotted from a \
                recording's own positions; Apple Maps, if you turn it on, downloads map tiles. \
                Nothing you record is ever uploaded.
                """)
        }
        .themedRows()
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: Self.version)
            // The key a calibration measurement would be filed under (R-10, R-72).
            LabeledContent("iPhone model", value: DeviceCalibration.modelIdentifier)
            // The first-run explainer is the only place the estimates are set out in full, so
            // it is worth being able to read it again (R-73).
            Button("Show the welcome screen again") {
                showsWelcomeAgain = true
                dismiss()
            }
        } header: {
            Text("About")
        } footer: {
            Text("Readout is free and open source, with no ads, no accounts and no tracking. It shows what an iPhone's own sensors can measure, and says plainly where every number comes from.")
        }
        .themedRows()
    }

    /// Says plainly whether this iPhone has a measured baseline behind the sliders, so
    /// nobody assumes a calibration that does not exist (P-2, R-72).
    private static var baselineNote: String {
        DeviceCalibration.hasEntryForThisDevice
            ? "A measured baseline for this iPhone model is applied as well."
            : "There is no measured baseline for this iPhone model, so these start from zero."
    }

    private static var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
