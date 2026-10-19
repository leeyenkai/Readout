import SwiftUI

/// Units, haptics, calibration, hidden tiles, About and Privacy (R-23).
struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(SensorHub.self) private var hub
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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

                Section {
                    Toggle("Point at true north", isOn: Binding(
                        get: { settings.usesTrueNorth },
                        set: { settings.usesTrueNorth = $0 }
                    ))
                } header: {
                    Text("Compass")
                } footer: {
                    Text("True north needs your location. Magnetic north is what the magnetometer sees.")
                }

                Section {
                    LabeledContent("Sound offset") {
                        Text("\(settings.soundCalibrationOffset, format: .number.precision(.fractionLength(0))) dB")
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { settings.soundCalibrationOffset },
                            set: { settings.soundCalibrationOffset = $0 }
                        ),
                        in: -20...20,
                        step: 1
                    )
                    LabeledContent("Light multiplier") {
                        Text(settings.lightCalibration, format: .number.precision(.fractionLength(2)))
                            .monospacedDigit()
                    }
                    Slider(
                        value: Binding(
                            get: { settings.lightCalibration },
                            set: { settings.lightCalibration = $0 }
                        ),
                        in: 0.25...4,
                        step: 0.05
                    )
                } header: {
                    Text("Calibration")
                } footer: {
                    Text("""
                        Sound and light are estimates, not calibrated measurements. If you \
                        have a reference meter to hand, nudge these until Readout agrees \
                        with it. \(Self.baselineNote)
                        """)
                }

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

                if !settings.hiddenReadings.isEmpty {
                    Section("Hidden readings") {
                        ForEach(Array(settings.hiddenReadings).sorted(by: { $0.rawValue < $1.rawValue })) { reading in
                            HStack {
                                Text(ReadingCatalog.descriptor(reading).name)
                                Spacer()
                                Button("Show") {
                                    settings.setHidden(false, for: reading)
                                }
                                .font(.subheadline)
                            }
                        }
                    }
                }

                Section {
                    LabeledContent("Data collected", value: "None")
                    LabeledContent("Network requests", value: "None")
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Everything is measured and kept on this iPhone. Readout has no accounts, no analytics and no network code at all. Microphone audio and camera frames are read in memory to work out a level and are never saved. Recordings stay here until you export them, and deleting Readout deletes them with it.")
                }

                Section {
                    LabeledContent("Version", value: Self.version)
                    LabeledContent("Readings", value: "\(ReadingCatalog.all.count)")
                } header: {
                    Text("About")
                } footer: {
                    Text("Readout is a hobby project. It shows what an iPhone's own sensors can measure, and says plainly where each number comes from.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Says plainly whether this iPhone has a measured baseline behind the sliders, so
    /// nobody assumes a calibration that does not exist (P-2, R-72).
    private static var baselineNote: String {
        DeviceCalibration.hasEntryForThisDevice
            ? "Readout also applies a measured baseline for this iPhone model."
            : "Readout has no measured baseline for this iPhone model, so these start from zero."
    }

    private static var version: String {
        let bundle = Bundle.main
        let short = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }
}
