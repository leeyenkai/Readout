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
    /// Draws the track on from its start as the panel appears — for a saved recording, whose
    /// whole route arrives at once. The live view's route builds up by itself.
    var drawsOn = false

    @Environment(AppSettings.self) private var settings
    @Environment(\.themeAccent) private var accent
    @State private var isConfirmingMaps = false

    private var distance: Double { RoutePlot.distance(route) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "Route", symbol: "map") {
                Text(ValueFormatting.format(distance, unit: .distance, units: settings.displayUnits).spoken)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Group {
                if settings.usesAppleMaps {
                    RouteMap(route: route, accent: accent)
                } else {
                    RouteTrace(route: route, accent: accent, drawsOn: drawsOn)
                }
            }
            .frame(height: 260)
            .clipShape(.rect(cornerRadius: Metrics.insetRadius))
            .transition(.blurReplace)

            footer
        }
        .motion(.readoutSmooth, value: settings.usesAppleMaps)
        .readoutCard(padding: 14)
        .appleMapsConsent(isPresented: $isConfirmingMaps)
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(route.count.formatted()) positions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            if settings.usesAppleMaps {
                Button("Use the plot", systemImage: "scribble") {
                    withReadoutAnimation { settings.usesAppleMaps = false }
                }
                .font(.caption.weight(.semibold))
            } else {
                Button("Show on Apple Maps", systemImage: "map") { isConfirmingMaps = true }
                    .font(.caption.weight(.semibold))
            }
        }

        Text(settings.usesAppleMaps
            ? "Apple Maps downloads its own map tiles. The route itself stays on this iPhone."
            : "Plotted from this recording's own positions — north up, no network needed.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// The route drawn from its own coordinates, with a scale bar and the two ends marked.
private struct RouteTrace: View {
    let route: [RecordedCoordinate]
    let accent: Color
    let drawsOn: Bool

    @State private var progress: CGFloat = 1
    @State private var showsEnd = true

    var body: some View {
        GeometryReader { geometry in
            let layout = RoutePlot.layout(route, in: geometry.size)
            ZStack {
                if let layout, layout.points.count > 1 {
                    RouteLine(points: layout.points)
                        .trim(from: 0, to: progress)
                        .stroke(accent, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
                        .shadow(color: accent.opacity(0.45), radius: 6)
                }
                Canvas { context, size in
                    guard let layout, !layout.points.isEmpty else { return }
                    mark(context, at: layout.points[0], colour: .green)
                    // The end is marked once the line has reached it.
                    if let last = layout.points.last, layout.points.count > 1, showsEnd {
                        mark(context, at: last, colour: .red)
                    }
                    drawScaleBar(context, size: size, metresPerPoint: layout.metresPerPoint)
                }
            }
        }
        .background(.quaternary.opacity(0.35))
        .onAppear {
            guard drawsOn, !UIAccessibility.isReduceMotionEnabled else { return }
            progress = 0
            showsEnd = false
            withAnimation(.easeInOut(duration: 1.4).delay(0.15)) {
                progress = 1
            } completion: {
                withAnimation(.readoutSpring) { showsEnd = true }
            }
        }
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
        return "Route plotted from \(route.count) positions, \(distance.spoken) long."
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
        .accessibilityLabel("Route on Apple Maps, \(route.count) positions")
    }
}

/// The track as a shape, so it can be drawn on with `trim`.
private struct RouteLine: Shape {
    let points: [CGPoint]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addLines(points)
        return path
    }
}
