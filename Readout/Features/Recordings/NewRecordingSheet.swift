import SwiftUI

/// New Recording: a checklist of readings and a sample rate, with the permissions a chosen
/// reading needs asked for right here (R-37, R-38, R-39).
struct NewRecordingSheet: View {
    /// Readings ticked when the sheet opens, from the Record button on a detail view or tool.
    var preselected: [ReadingID] = []

    @Environment(SensorHub.self) private var hub
    @Environment(RecordingService.self) private var recorder
    @Environment(\.dismiss) private var dismiss

    @State private var chosen: Set<ReadingID> = []
    @State private var rate: RecordingRate = .medium
    @State private var isStarting = false
    @State private var refused: [SensorPermission] = []
    @State private var didPreselect = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Sample rate", selection: $rate) {
                        ForEach(RecordingRate.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(isStarting)
                } header: {
                    Text("Sample rate")
                } footer: {
                    Text("\(rate.detail). High applies to the motion readings; location, air pressure and the step counter arrive at their own rate whatever you choose.")
                }

                ForEach(ReadingGroup.allCases) { group in
                    let readings = hub.availableReadings(in: group)
                    if !readings.isEmpty {
                        Section(group.title) {
                            ForEach(readings) { descriptor in
                                row(for: descriptor)
                            }
                        }
                    }
                }

                Section {
                    Text("Recording keeps going while Readout is open. Leaving the app stops the session and saves what it has.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("New Recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task { await start() }
                    }
                    .fontWeight(.semibold)
                    .disabled(chosen.isEmpty || isStarting)
                }
            }
            .alert("Some readings were left out", isPresented: isShowingRefusal) {
                Button("OK") { refused = [] }
            } message: {
                Text(refusalMessage)
            }
            .onAppear(perform: preselectOnce)
        }
    }

    private func row(for descriptor: ReadingDescriptor) -> some View {
        let isChosen = chosen.contains(descriptor.id)
        return Button {
            if isChosen {
                chosen.remove(descriptor.id)
            } else {
                chosen.insert(descriptor.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: descriptor.symbol)
                    .font(.footnote)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(descriptor.name)
                        .foregroundStyle(.primary)
                    if case .needsPermission(let permission) = hub.availability(descriptor.id) {
                        Text("Needs \(permission.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if case .denied(let permission) = hub.availability(descriptor.id) {
                        Text("\(permission.title) is off in Settings")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if descriptor.recordingCadence == .free, rate == .high {
                        Text("Records at its own rate")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .font(.body)
                    .foregroundStyle(isChosen ? Color.accentColor : Color.secondary)
            }
            // Without this the gap between the name and the tick is not a tap target, and
            // half the row does nothing.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(isStarting)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
    }

    /// Asks for whatever the chosen readings need, then starts with the ones that are allowed
    /// (R-38). A reading whose permission was refused is named rather than silently dropped.
    private func start() async {
        isStarting = true
        for permission in neededPermissions {
            await hub.requestPermission(permission)
        }
        let usable = chosen.filter { hub.availability($0).isUsable }
        let missing = chosen.subtracting(usable)
            .compactMap { ReadingCatalog.descriptor($0).permission }
        isStarting = false

        guard !usable.isEmpty else {
            refused = Array(Set(missing)).sorted { $0.title < $1.title }
            return
        }
        recorder.start(readings: Array(usable), rate: rate)
        dismiss()
    }

    /// Only the permissions a chosen reading is actually waiting on. Asking for one that has
    /// already been granted means waiting on a framework callback for nothing — and in the
    /// Simulator, where there is no prompt to answer, waiting for ever.
    private var neededPermissions: [SensorPermission] {
        let permissions = chosen.compactMap { reading -> SensorPermission? in
            guard case .needsPermission(let permission) = hub.availability(reading) else { return nil }
            return permission
        }
        return Array(Set(permissions)).sorted { $0.title < $1.title }
    }

    private var isShowingRefusal: Binding<Bool> {
        Binding(get: { !refused.isEmpty }, set: { if !$0 { refused = [] } })
    }

    private var refusalMessage: String {
        let names = refused.map(\.title).joined(separator: " and ")
        guard !names.isEmpty else {
            return "None of the chosen readings can run on this iPhone."
        }
        return "Readout needs \(names) access to record what you chose. You can allow it in Settings."
    }

    private func preselectOnce() {
        guard !didPreselect else { return }
        didPreselect = true
        chosen = Set(preselected.filter { hub.availability($0) != .unavailable })
    }
}
