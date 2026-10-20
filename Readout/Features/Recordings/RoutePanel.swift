import MapKit
import SwiftUI

/// The route a session recorded, as a plot of its own fixes or — if the user has asked for it
/// — on Apple Maps (R-76).
///
/// The plot is what shows by default, and it is the honest default: Readout makes no network
/// requests, and a street map is somebody else's tiles fetched over one (R-59). The plot is
/// drawn from the session's own CSV, so it works with the radio off and nothing about the
/// recording leaves the phone. Apple Maps is offered beside it, once, with the trade spelled
/// out, and stays off until somebody says otherwise.
struct RoutePanel: View {
    let route: [RecordedCoordinate]

    @Environment(AppSettings.self) private var settings
    @Environment(\.themeAccent) private var accent
    @State private var isConfirmingMaps = false

    private var distance: Double { RoutePlot.distance(route) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if settings.usesAppleMaps {
                RouteMap(route: route, accent: accent)
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: 18))
            } else {
                RouteTrace(route: route, accent: accent)
                    .frame(height: 260)
                    .clipShape(.rect(cornerRadius: 18))
            }

            footer
        }
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .confirmationDialog(
            "Show routes on Apple Maps?",
            isPresented: $isConfirmingMaps,
            titleVisibility: .visible
        ) {
            Button("Show on Apple Maps") { settings.usesAppleMaps = true }
            Button("Keep the plot", role: .cancel) {}
        } message: {
            Text("""
                Apple Maps downloads its map tiles, so this is the one part of Readout that \
                uses the network. Your recordings are not uploaded — only the part of the \
                world the route covers is asked for, by iOS, the same as in any other app \
                showing a map. The plot needs no network at all. You can switch this back off \
                in Settings.
                """)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "map")
                .font(.footnote)
                .foregroundStyle(.tint)
            Text("Route")
                .font(.headline)
            Spacer(minLength: 0)
            Text(ValueFormatting.format(distance, unit: .distance, units: settings.displayUnits).spoken)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(route.count.formatted()) fixes")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
            if settings.usesAppleMaps {
                Button("Use the plot") { settings.usesAppleMaps = false }
                    .font(.caption.weight(.semibold))
            } else {
                Button("Show on Apple Maps") { isConfirmingMaps = true }
                    .font(.caption.weight(.semibold))
            }
        }

        Text(settings.usesAppleMaps
            ? "Apple Maps fetches its own tiles over the network. The route itself stays on this iPhone."
            : "Plotted from this session's own fixes — north up, no network, no map server.")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

/// The route drawn from its own coordinates, with a scale bar and the two ends marked.
private struct RouteTrace: View {
    let route: [RecordedCoordinate]
    let accent: Color

    var body: some View {
        Canvas { context, size in
            guard let layout = RoutePlot.layout(route, in: size), !layout.points.isEmpty else {
                return
            }

            if layout.points.count > 1 {
                var path = Path()
                path.addLines(layout.points)
                context.stroke(
                    path,
                    with: .color(accent),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
            }

            mark(context, at: layout.points[0], colour: .green)
            if let last = layout.points.last, layout.points.count > 1 {
                mark(context, at: last, colour: .red)
            }

            drawScaleBar(context, size: size, metresPerPoint: layout.metresPerPoint)
        }
        .background(.quaternary.opacity(0.4))
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    /// A filled dot with a ring round it, so the ends read against the line and the backdrop.
    private func mark(_ context: GraphicsContext, at point: CGPoint, colour: Color) {
        let outer = CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)
        context.fill(Path(ellipseIn: outer), with: .color(.white))
        let inner = outer.insetBy(dx: 2.5, dy: 2.5)
        context.fill(Path(ellipseIn: inner), with: .color(colour))
    }

    private func drawScaleBar(_ context: GraphicsContext, size: CGSize, metresPerPoint: Double) {
        guard let bar = RoutePlot.scaleBar(
            metresPerPoint: metresPerPoint,
            maximumWidth: max(size.width * 0.35, 1)
        ) else { return }

        let y = size.height - 18
        let left = 14.0
        var rule = Path()
        rule.move(to: CGPoint(x: left, y: y))
        rule.addLine(to: CGPoint(x: left + bar.width, y: y))
        rule.move(to: CGPoint(x: left, y: y - 4))
        rule.addLine(to: CGPoint(x: left, y: y + 4))
        rule.move(to: CGPoint(x: left + bar.width, y: y - 4))
        rule.addLine(to: CGPoint(x: left + bar.width, y: y + 4))
        context.stroke(rule, with: .color(.secondary), lineWidth: 1.5)

        context.draw(
            Text(Self.scaleText(bar.metres)).font(.caption2).foregroundStyle(.secondary),
            at: CGPoint(x: left, y: y - 12),
            anchor: .bottomLeading
        )
    }

    /// The scale bar's own label stays metric: it measures the drawing, not a reading, and a
    /// round 500 m becomes an unround 1,640 ft.
    private static func scaleText(_ metres: Double) -> String {
        metres >= 1_000
            ? "\(ValueFormatting.decimal(metres / 1_000, digits: metres >= 10_000 ? 0 : 1)) km"
            : "\(ValueFormatting.decimal(metres, digits: 0)) m"
    }

    private var accessibilityLabel: String {
        let distance = ValueFormatting.format(RoutePlot.distance(route), unit: .distance, units: .metricDefault)
        return "Route plotted from \(route.count) fixes, \(distance.spoken) long."
    }
}

/// The same route on Apple Maps, for anyone who has asked for it.
private struct RouteMap: View {
    let route: [RecordedCoordinate]
    let accent: Color

    private var coordinates: [CLLocationCoordinate2D] {
        route.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        Map(initialPosition: .automatic, interactionModes: [.pan, .zoom]) {
            if coordinates.count > 1 {
                MapPolyline(coordinates: coordinates)
                    .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
            if let start = coordinates.first {
                Marker("Start", systemImage: "flag", coordinate: start)
                    .tint(.green)
            }
            if let end = coordinates.last, coordinates.count > 1 {
                Marker("End", systemImage: "flag.checkered", coordinate: end)
                    .tint(.red)
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .accessibilityLabel("Route on Apple Maps, \(route.count) fixes")
    }
}
