import SwiftUI

/// The home grid: two columns of glass tiles under four group headers (R-15).
struct ReadingsView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @State private var isEditing = false
    @State private var isShowingSettings = false
    /// Which readings this grid has asked for, so they can be given back exactly once (R-64).
    @State private var activated: Set<ReadingID> = []

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ReadingGroup.allCases) { group in
                        let readings = visibleReadings(in: group)
                        if !readings.isEmpty {
                            Section {
                                ForEach(readings) { descriptor in
                                    tile(for: descriptor)
                                }
                            } header: {
                                GroupHeader(group: group)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Readout")
            .navigationDestination(for: ReadingID.self) { reading in
                ReadingDetailView(reading: reading)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "Done" : "Edit") {
                        withAnimation(.snappy) { isEditing.toggle() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onAppear(perform: syncActivations)
            .onDisappear(perform: deactivateAll)
            .onChange(of: settings.hiddenReadings) { _, _ in syncActivations() }
            .onChange(of: isEditing) { _, _ in syncActivations() }
            .safeAreaInset(edge: .top) {
                if isEditing {
                    EditModeBanner(hiddenCount: settings.hiddenReadings.count) {
                        settings.showAllReadings()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tile(for descriptor: ReadingDescriptor) -> some View {
        let availability = hub.availability(descriptor.id)
        let tile = ReadingTile(
            descriptor: descriptor,
            availability: availability,
            sample: hub.sample(descriptor.id),
            trail: hub.trail(descriptor.id),
            units: settings.displayUnits,
            isDimmed: isEditing && settings.isHidden(descriptor.id)
        )

        if isEditing {
            Button {
                withAnimation(.snappy) {
                    settings.setHidden(!settings.isHidden(descriptor.id), for: descriptor.id)
                }
            } label: {
                tile.overlay(alignment: .topTrailing) {
                    Image(systemName: settings.isHidden(descriptor.id) ? "eye.slash.circle.fill" : "eye.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(settings.isHidden(descriptor.id) ? .secondary : Color.accentColor)
                        .padding(8)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(settings.isHidden(descriptor.id) ? "Show \(descriptor.name)" : "Hide \(descriptor.name)")
        } else {
            NavigationLink(value: descriptor.id) {
                tile
            }
            .buttonStyle(.plain)
        }
    }

    /// Starts the readings on screen and stops the ones that have left it. The camera,
    /// microphone and proximity sensor are left alone: they wait to be tapped (R-19, R-64).
    private func syncActivations() {
        let wanted = Set(
            ReadingGroup.allCases
                .flatMap(visibleReadings(in:))
                .filter { $0.activation == .whileVisible }
                .map(\.id)
        )
        for reading in wanted.subtracting(activated) {
            hub.activate(reading)
        }
        for reading in activated.subtracting(wanted) {
            hub.deactivate(reading)
        }
        activated = wanted
    }

    private func deactivateAll() {
        for reading in activated {
            hub.deactivate(reading)
        }
        activated = []
    }

    /// Hidden tiles disappear from the grid but come back in edit mode so they can be
    /// restored (R-22). A reading the device lacks never appears at all (R-21).
    private func visibleReadings(in group: ReadingGroup) -> [ReadingDescriptor] {
        hub.availableReadings(in: group).filter { isEditing || !settings.isHidden($0.id) }
    }
}

private struct GroupHeader: View {
    let group: ReadingGroup

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: group.symbol)
                .font(.caption)
            Text(group.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
        }
        .foregroundStyle(.secondary)
        .padding(.top, 12)
        .padding(.bottom, 2)
        .textCase(nil)
    }
}

private struct EditModeBanner: View {
    let hiddenCount: Int
    let onShowAll: () -> Void

    var body: some View {
        HStack {
            Text(hiddenCount == 0 ? "Tap a tile to hide it" : "\(hiddenCount) hidden")
                .font(.footnote)
            Spacer()
            if hiddenCount > 0 {
                Button("Show all", action: onShowAll)
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }
}
