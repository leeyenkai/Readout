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
    /// Set when some of the chosen readings can run and some cannot, so the user decides
    /// whether to start without them rather than finding out from the recording.
    @State private var partial: PartialStart?
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
                .themedRows()

                ForEach(ReadingGroup.allCases) { group in
                    let readings = hub.availableReadings(in: group)
                    if !readings.isEmpty {
                        Section(group.title) {
                            ForEach(readings) { descriptor in
                                row(for: descriptor)
                            }
                        }
                        .themedRows()
                    }
                }

                // What happens when the phone goes in a pocket, said before the session starts
                // rather than discovered at the end of a journey (R-82).
                if !chosen.isEmpty {
                    Section {
                        let verdict = recorder.backgroundVerdict(for: chosen)
                        Label {
                            Text(verdict.summary)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } icon: {
                            Image(systemName: verdict.symbol)
                                .foregroundStyle(verdict.continuesInBackground
                                    ? AnyShapeStyle(.tint)
                                    : AnyShapeStyle(.secondary))
                        }

                        if verdict == .stopsWithoutLocation, canAddCoordinates {
                            Button("Add Coordinates so it keeps running", systemImage: "plus.circle.fill") {
                                withReadoutAnimation { _ = chosen.insert(.coordinates) }
                            }
                            .font(.footnote.weight(.semibold))
                        }
                    } header: {
                        Text("Leaving the app")
                    }
                    .themedRows()
                    .transition(.opacity)
                }
            }
            .motion(.readoutSnappy, value: chosen.isEmpty)
            .navigationTitle("New recording")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isStarting {
                        ProgressView()
                    } else {
                        Button("Start") {
                            Task { await start() }
                        }
                        .fontWeight(.semibold)
                        .disabled(chosen.isEmpty)
                    }
                }
            }
            .alert("Nothing can be recorded yet", isPresented: isShowingRefusal) {
                Button("OK") { refused = [] }
            } message: {
                Text(refusalMessage)
            }
            .alert(
                partial.map { "Start without \($0.leftOutNames)?" } ?? "",
                isPresented: Binding(get: { partial != nil }, set: { if !$0 { partial = nil } }),
                presenting: partial
            ) { start in
                Button("Start") {
                    recorder.start(readings: start.usable, rate: rate)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                Button("Cancel", role: .cancel) {}
            } message: { start in
                Text("\(start.permissionNames) \(start.permissionCount == 1 ? "isn't" : "aren't") allowed, so \(start.leftOutNames) would be left out. The rest can record now.")
            }
            .onAppear(perform: preselectOnce)
            .themedSurface()
        }
    }

    private func row(for descriptor: ReadingDescriptor) -> some View {
        let isChosen = chosen.contains(descriptor.id)
        return Button {
            withReadoutAnimation {
                if isChosen {
                    chosen.remove(descriptor.id)
                } else {
                    chosen.insert(descriptor.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: descriptor.symbol)
                    .font(.footnote)
                    .foregroundStyle(.tint)
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
                    .font(.title3)
                    .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
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
    /// (R-38). A reading whose permission was refused is named rather than silently dropped:
    /// with nothing allowed the sheet says so, and with some allowed it asks before starting
    /// without the rest. Starting regardless used to drop them without a word.
    private func start() async {
        isStarting = true
        for permission in neededPermissions {
            await hub.requestPermission(permission)
        }
        let usable = chosen.filter { hub.availability($0).isUsable }
        let leftOut = chosen.subtracting(usable)
        let missing = leftOut.compactMap { ReadingCatalog.descriptor($0).permission }
        isStarting = false

        guard !usable.isEmpty else {
            refused = Array(Set(missing)).sorted { $0.title < $1.title }
            return
        }
        guard leftOut.isEmpty else {
            partial = PartialStart(
                usable: Array(usable),
                leftOut: ReadingCatalog.all.map(\.id).filter(leftOut.contains),
                permissions: Array(Set(missing)).sorted { $0.title < $1.title }
            )
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

    /// Whether offering to add Coordinates would help: on a device that cannot locate itself
    /// at all, the offer would be a button that changes nothing (R-7).
    private var canAddCoordinates: Bool {
        hub.availability(.coordinates) != .unavailable && !chosen.contains(.coordinates)
    }

    /// The readings that can start and the ones that would be left out, for the question
    /// asked before starting without them.
    private struct PartialStart {
        let usable: [ReadingID]
        let leftOut: [ReadingID]
        let permissions: [SensorPermission]

        var leftOutNames: String {
            ListFormatter.localizedString(byJoining: leftOut.map { ReadingCatalog.descriptor($0).name })
        }

        var permissionNames: String {
            ListFormatter.localizedString(byJoining: permissions.map(\.title))
        }

        var permissionCount: Int { permissions.count }
    }

    private func preselectOnce() {
        guard !didPreselect else { return }
        didPreselect = true
        chosen = Set(preselected.filter { hub.availability($0) != .unavailable })
    }
}
