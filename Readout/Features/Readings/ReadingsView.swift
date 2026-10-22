import SwiftUI

/// The home grid: two columns of glass tiles under four group headers (R-15).
struct ReadingsView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @State private var isEditing = false
    @State private var isShowingSettings = false
    /// Set from Settings' "Show the welcome screen again", and acted on once Settings has
    /// gone: putting the welcome sheet up while Settings was still being dismissed raced it.
    @State private var showsWelcomeAfterSettings = false
    /// The grid's leases, so every reading it started is given back exactly once (R-64).
    @State private var leases: [ReadingID: SensorLease] = [:]
    /// The tiles settle in once, as the app opens — not every time one scrolls into view.
    @State private var hasArrived = false
    @Namespace private var zoom

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if isGridEmpty {
                    AllHiddenNotice {
                        withReadoutAnimation { settings.showAllReadings() }
                    }
                    .padding(.top, 48)
                    .transition(.blurReplace)
                }

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ReadingGroup.allCases) { group in
                        section(for: group)
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.bottom, Metrics.bottomPadding)
            }
            .scrollIndicators(.hidden)
            .navigationTitle("Readout")
            .navigationDestination(for: ReadingID.self) { reading in
                ReadingDetailView(reading: reading)
                    .navigationTransition(.zoom(sourceID: reading, in: zoom))
            }
            // A reading's detail view can open its instrument: Orientation opens the 3D view.
            .navigationDestination(for: Tool.self) { tool in
                tool.destination
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isEditing ? "Done" : "Edit") {
                        withReadoutAnimation { isEditing.toggle() }
                    }
                    .fontWeight(isEditing ? .semibold : .regular)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
            }
            .sheet(isPresented: $isShowingSettings, onDismiss: {
                if showsWelcomeAfterSettings {
                    showsWelcomeAfterSettings = false
                    settings.hasSeenWelcome = false
                }
            }) {
                SettingsView(showsWelcomeAgain: $showsWelcomeAfterSettings)
            }
            .onAppear {
                syncActivations()
                // Long enough for the first screenful to have arrived; after that a tile
                // scrolling into view simply appears.
                Task {
                    try? await Task.sleep(for: .seconds(1.2))
                    hasArrived = true
                }
            }
            .onDisappear(perform: deactivateAll)
            .onChange(of: settings.hiddenReadings) { _, _ in syncActivations() }
            .onChange(of: isEditing) { _, _ in syncActivations() }
            .safeAreaInset(edge: .top) {
                if isEditing {
                    EditModeBanner(
                        hiddenCount: settings.hiddenReadings.count,
                        onShowAll: { withReadoutAnimation { settings.showAllReadings() } },
                        onResetOrder: { withReadoutAnimation { settings.resetOrder() } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .motion(.readoutSnappy, value: isEditing)
            .themedSurface()
        }
    }

    @ViewBuilder
    private func section(for group: ReadingGroup) -> some View {
        let readings = visibleReadings(in: group)
        if !readings.isEmpty {
            Section {
                ForEach(Array(readings.enumerated()), id: \.element.id) { index, descriptor in
                    tile(for: descriptor)
                        .arrival(delay: arrivalDelay(group: group, index: index), isActive: !hasArrived)
                }
            } header: {
                GroupHeader(group: group)
                    .arrival(delay: arrivalDelay(group: group, index: 0), isActive: !hasArrived)
            }
        }
    }

    /// A short stagger, group by group, so the grid fills in from the top.
    private func arrivalDelay(group: ReadingGroup, index: Int) -> Double {
        let groupIndex = ReadingGroup.allCases.firstIndex(of: group) ?? 0
        return Double(groupIndex) * 0.08 + Double(index) * 0.035
    }

    @ViewBuilder
    private func tile(for descriptor: ReadingDescriptor) -> some View {
        // The tile reads its own reading, so a new sample redraws that tile and nothing
        // else; the grid itself never reads a sample (R-65).
        let tile = LiveReadingTile(
            descriptor: descriptor,
            units: settings.displayUnits,
            isDimmed: isEditing && settings.isHidden(descriptor.id)
        )

        if isEditing {
            // A tap gesture rather than a Button: a Button's own gesture wins the long press,
            // and the drag never starts.
            tile
                .overlay(alignment: .topTrailing) {
                    Image(systemName: settings.isHidden(descriptor.id) ? "eye.slash.circle.fill" : "eye.circle.fill")
                        .font(.title3)
                        .symbolRenderingMode(.hierarchical)
                        // Erased, because a ternary between two different ShapeStyles has no
                        // common type for the compiler to settle on.
                        .foregroundStyle(settings.isHidden(descriptor.id)
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.tint))
                        .padding(8)
                }
                .contentShape(.rect(cornerRadius: Metrics.tileRadius))
                .onTapGesture {
                    withReadoutAnimation {
                        settings.setHidden(!settings.isHidden(descriptor.id), for: descriptor.id)
                    }
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(settings.isHidden(descriptor.id) ? "Show \(descriptor.name)" : "Hide \(descriptor.name)")
                .draggable(descriptor.id) {
                    // A plain label as the lift preview: dragging a live, redrawing tile
                    // makes the drag image flicker.
                    Label(descriptor.name, systemImage: descriptor.symbol)
                        .padding(10)
                        .glassEffect(.regular, in: .capsule)
                }
            .dropDestination(for: ReadingID.self) { dropped, _ in
                guard let moved = dropped.first else { return false }
                withReadoutAnimation { settings.move(moved, before: descriptor.id) }
                return true
            }
            // VoiceOver cannot drag, so the same reordering is reachable as actions.
            .accessibilityActions {
                ForEach(reorderTargets(for: descriptor), id: \.id) { target in
                    Button("Move before \(target.name)") {
                        settings.move(descriptor.id, before: target.id)
                    }
                }
            }
        } else {
            NavigationLink(value: descriptor.id) {
                tile
                    .matchedTransitionSource(id: descriptor.id, in: zoom)
            }
            .buttonStyle(.pressableCard)
            // Long-press is the other way into edit mode, alongside the Edit button (R-22).
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    withReadoutAnimation { isEditing = true }
                }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: isEditing) { _, editing in
                editing && settings.hapticsEnabled
            }
        }
    }

    /// Hiding every tile is a state edit mode can reach, so the grid says so rather than
    /// sitting blank (R-22).
    private var isGridEmpty: Bool {
        ReadingGroup.allCases.allSatisfy { visibleReadings(in: $0).isEmpty }
    }

    /// The other tiles in this reading's group, as VoiceOver move targets.
    private func reorderTargets(for descriptor: ReadingDescriptor) -> [ReadingDescriptor] {
        visibleReadings(in: descriptor.group).filter { $0.id != descriptor.id }
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
        for reading in wanted.subtracting(leases.keys) {
            leases[reading] = hub.activate(reading)
        }
        for reading in Set(leases.keys).subtracting(wanted) {
            hub.release(leases.removeValue(forKey: reading))
        }
    }

    private func deactivateAll() {
        for lease in leases.values {
            hub.release(lease)
        }
        leases = [:]
    }

    /// Hidden tiles disappear from the grid but come back in edit mode so they can be
    /// restored (R-22). A reading the device lacks never appears at all (R-21).
    private func visibleReadings(in group: ReadingGroup) -> [ReadingDescriptor] {
        settings.ordered(hub.availableReadings(in: group).filter { isEditing || !settings.isHidden($0.id) })
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

private struct AllHiddenNotice: View {
    let onShowAll: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No tiles on the grid", systemImage: "square.dashed")
        } description: {
            Text("Every reading is hidden. Bring them all back, or tap Edit to pick the ones you want.")
        } actions: {
            Button("Show all readings", action: onShowAll)
                .buttonStyle(.glassProminent)
        }
    }
}

private struct EditModeBanner: View {
    let hiddenCount: Int
    let onShowAll: () -> Void
    let onResetOrder: () -> Void

    var body: some View {
        HStack {
            Text(hiddenCount == 0 ? "Tap to hide · drag to reorder" : "\(hiddenCount) hidden")
                .font(.footnote)
                .contentTransition(.numericText())
            Spacer()
            if hiddenCount > 0 {
                Button("Show all", action: onShowAll)
                    .font(.footnote.weight(.semibold))
            }
            Button("Reset order", action: onResetOrder)
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 16)
    }
}
