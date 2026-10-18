import SwiftUI

/// Surface mode when the phone is flat, edge mode when it is on its side, switching
/// automatically; angle to a tenth of a degree, a zero calibration and hold to freeze (R-32).
struct SpiritLevelView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var isHeld = false
    @State private var frozen: Vector3?
    @State private var zeroX: Double = 0
    @State private var zeroY: Double = 0

    var body: some View {
        VStack(spacing: 20) {
            if let gravity {
                let isSurface = LevelMaths.isSurfaceMode(gravity: gravity)
                Text(isSurface ? "Surface" : "Edge")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if isSurface {
                    SurfaceLevel(
                        angles: angles(gravity),
                        isLevel: isLevel,
                        reduceMotion: reduceMotion
                    )
                } else {
                    EdgeLevel(angle: edgeAngle(gravity), isLevel: isLevel)
                }

                readout(gravity: gravity, isSurface: isSurface)
            } else {
                ProgressView("Waiting for device motion…")
                    .frame(maxHeight: .infinity)
            }

            controls
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .navigationTitle("Spirit level")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { hub.activate(.orientation, rate: .display) }
        .onDisappear { hub.deactivate(.orientation, rate: .display) }
        .sensoryFeedback(trigger: isLevel) { _, level in
            // A tap as the level reaches 0° (R-51).
            settings.hapticsEnabled && level ? .impact(weight: .light) : nil
        }
    }

    private var gravity: Vector3? {
        frozen ?? hub.gravity
    }

    private func angles(_ gravity: Vector3) -> (x: Double, y: Double) {
        let raw = LevelMaths.surfaceAngles(gravity: gravity)
        return (x: raw.x - zeroX, y: raw.y - zeroY)
    }

    private func edgeAngle(_ gravity: Vector3) -> Double {
        LevelMaths.edgeAngle(gravity: gravity) - zeroX
    }

    private var isLevel: Bool {
        guard let gravity else { return false }
        if LevelMaths.isSurfaceMode(gravity: gravity) {
            let angles = angles(gravity)
            return abs(angles.x) < 0.3 && abs(angles.y) < 0.3
        }
        return abs(edgeAngle(gravity)) < 0.3
    }

    @ViewBuilder
    private func readout(gravity: Vector3, isSurface: Bool) -> some View {
        HStack(spacing: 24) {
            if isSurface {
                let angles = angles(gravity)
                angleValue("X", angles.x)
                angleValue("Y", angles.y)
            } else {
                angleValue("Angle", edgeAngle(gravity))
            }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }

    private func angleValue(_ label: String, _ value: Double) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("\(ValueFormatting.decimal(value, digits: 1))°")
                .font(.system(.title, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(abs(value) < 0.3 ? Color.green : Color.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(ValueFormatting.decimal(value, digits: 1)) degrees")
    }

    private var controls: some View {
        HStack(spacing: 10) {
            Button(isHeld ? "Release" : "Hold") {
                isHeld.toggle()
                frozen = isHeld ? hub.gravity : nil
            }
            .buttonStyle(.glass)

            Button("Zero") {
                guard let gravity = hub.gravity else { return }
                if LevelMaths.isSurfaceMode(gravity: gravity) {
                    let raw = LevelMaths.surfaceAngles(gravity: gravity)
                    zeroX = raw.x
                    zeroY = raw.y
                } else {
                    zeroX = LevelMaths.edgeAngle(gravity: gravity)
                    zeroY = 0
                }
            }
            .buttonStyle(.glass)

            if zeroX != 0 || zeroY != 0 {
                Button("Clear zero") {
                    zeroX = 0
                    zeroY = 0
                }
                .buttonStyle(.glass)
            }
        }
        .font(.subheadline.weight(.medium))
    }
}

/// The bubble, for a phone lying flat.
private struct SurfaceLevel: View {
    let angles: (x: Double, y: Double)
    let isLevel: Bool
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let radius = size / 2
            // 15° of tilt moves the bubble to the edge of the circle.
            let offsetX = (angles.x / 15).clamped(to: -1...1) * (radius - 26)
            let offsetY = (angles.y / 15).clamped(to: -1...1) * (radius - 26)

            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 1.5)
                Circle()
                    .stroke(.tertiary, lineWidth: 1)
                    .frame(width: 52, height: 52)
                Path { path in
                    path.move(to: CGPoint(x: radius - 14, y: radius))
                    path.addLine(to: CGPoint(x: radius + 14, y: radius))
                    path.move(to: CGPoint(x: radius, y: radius - 14))
                    path.addLine(to: CGPoint(x: radius, y: radius + 14))
                }
                .stroke(.tertiary, lineWidth: 1)

                Circle()
                    .fill(isLevel ? Color.green : Color.secondary)
                    .frame(width: 44, height: 44)
                    .offset(x: offsetX, y: offsetY)
                    .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.2), value: angles.x)
                    .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.2), value: angles.y)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// The bar, for a phone standing on an edge.
private struct EdgeLevel: View {
    let angle: Double
    let isLevel: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.quaternary, lineWidth: 1.5)
                    .frame(height: 76)
                RoundedRectangle(cornerRadius: 10)
                    .fill(isLevel ? Color.green : Color.secondary)
                    .frame(width: 60, height: 60)
                    .offset(x: (angle / 15).clamped(to: -1...1) * 110)
                    .animation(.interactiveSpring(duration: 0.2), value: angle)
                Rectangle()
                    .fill(.tertiary)
                    .frame(width: 1, height: 76)
            }
            .padding(.horizontal, 20)

            Image(systemName: "iphone.gen3")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(angle.clamped(to: -30...30)))
        }
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }
}
