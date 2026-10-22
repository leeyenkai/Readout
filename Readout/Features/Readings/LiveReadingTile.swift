import SwiftUI

/// A tile that reads its own reading from the hub.
///
/// The grid used to read every tile's sample in its own body, so each new value from any
/// sensor redrew all nineteen tiles. Wrapped like this, a sample redraws the one tile it
/// belongs to, and `ReadingTile` itself stays a plain view that is handed its values (R-65).
struct LiveReadingTile: View {
    let descriptor: ReadingDescriptor
    let units: DisplayUnits
    var isDimmed = false

    @Environment(SensorHub.self) private var hub

    var body: some View {
        ReadingTile(
            descriptor: descriptor,
            availability: hub.availability(descriptor.id),
            sample: hub.sample(descriptor.id),
            trail: hub.trail(descriptor.id),
            units: units,
            isDimmed: isDimmed
        )
    }
}
