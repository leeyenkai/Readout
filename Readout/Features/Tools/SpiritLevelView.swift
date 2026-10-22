import SwiftUI

/// Surface mode when the phone is flat, edge mode when it stands on any of its four edges,
/// switching automatically; angle to a tenth of a degree, a zero that is kept per mode, and
/// Hold to freeze the reading (R-32).
struct SpiritLevelView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings

    @State private var lease: SensorLease?
    @State private var frozen: Vector3?
    @Namespace private var bubbleSpace

    private var isHeld: Bool { frozen != nil }

    var body: some View {
        ReadoutScreen {
            if let gravity {
                let isSurface = LevelMaths.isSurfaceMode(gravity: gravity)
                modeBadges(isSurface: isSurface, gravity: gravity)

                Group {
                    if isSurface {
                        SurfaceVial(
                            offset: surfaceOffset(gravity),
                            isLevel: isLevel(gravity),
                            namespace: bubbleSpace
                        )
                        .transition(.blurReplace)
                    } else {
                        EdgeVial(
                            offset: LevelMaths.edgeBubbleOffset(angle: settings.levelZero.edgeAngle(gravity: gravity)),
                            quarterTurns: LevelMaths.edgeQuarterTurns(gravity: gravity),
                            isLevel: isLevel(gravity),
                            namespace: bubbleSpace
                        )
                        .transition(.blurReplace)
                    }
                }
                .motion(.readoutSmooth, value: isSurface)

                readout(gravity: gravity, isSurface: isSurface)
                controls(gravity: gravity, isSurface: isSurface)
            } else {
                WaitingLabel(text: "Waiting for the motion sensors…")
                    .padding(.top, 120)
            }
        }
        .navigationTitle("Spirit level")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.orientation])
            }
        }
        .onAppear {
            guard lease == nil else { return }
            lease = hub.activate(.orientation, rate: .display)
        }
        .onDisappear {
            hub.release(lease)
            lease = nil
        }
        .sensoryFeedback(trigger: gravity.map(isLevel) ?? false) { _, level in
            // A tap as the level reaches 0° (R-51).
            settings.hapticsEnabled && level ? .impact(weight: .light) : nil
        }
    }

    /// What is on screen: the held reading if Hold is on, otherwise the live one.
    private var gravity: Vector3? {
        frozen ?? hub.gravity
    }

    private func surfaceOffset(_ gravity: Vector3) -> CGSize {
        let angles = settings.levelZero.surfaceAngles(gravity: gravity)
        let offset = LevelMaths.bubbleOffset(x: angles.x, y: angles.y)
        return CGSize(width: offset.x, height: offset.y)
    }

    private func isLevel(_ gravity: Vector3) -> Bool {
        if LevelMaths.isSurfaceMode(gravity: gravity) {
            let angles = settings.levelZero.surfaceAngles(gravity: gravity)
            return abs(angles.x) < 0.3 && abs(angles.y) < 0.3
        }
        return abs(settings.levelZero.edgeAngle(gravity: gravity)) < 0.3
    }

    private func isZeroed(_ gravity: Vector3, isSurface: Bool) -> Bool {
        isSurface
            ? settings.levelZero.isSurfaceZeroed
            : settings.levelZero.isEdgeZeroed(quarterTurns: LevelMaths.edgeQuarterTurns(gravity: gravity))
    }

    private func modeBadges(isSurface: Bool, gravity: Vector3) -> some View {
        HStack(spacing: 8) {
            Label(isSurface ? "Lying flat" : "On its edge", systemImage: isSurface ? "circle.circle" : "capsule")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
            if isHeld {
                StatusBadge(text: "Held", symbol: "pause.fill")
            }
            if isZeroed(gravity, isSurface: isSurface) {
                StatusBadge(text: "Zeroed", symbol: "scope", tint: .secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .motion(.readoutSnappy, value: isHeld)
        .motion(.readoutSnappy, value: isZeroed(gravity, isSurface: isSurface))
        .padding(.top, 4)
    }

    @ViewBuilder
    private func readout(gravity: Vector3, isSurface: Bool) -> some View {
        let level = isLevel(gravity)
        HStack(spacing: 0) {
            if isSurface {
                let angles = settings.levelZero.surfaceAngles(gravity: gravity)
                angleValue("Left to right", angles.x, axis: .x, isLevel: level)
                angleValue("Front to back", angles.y, axis: .y, isLevel: level)
            } else {
                angleValue("From level", settings.levelZero.edgeAngle(gravity: gravity), axis: nil, isLevel: level)
            }
        }
        .readoutCard(padding: 14)
    }

    private func angleValue(_ label: String, _ value: Double, axis: Axis?, isLevel: Bool) -> some View {
        let text = "\(ValueFormatting.decimal(value, digits: 1))°"
        return VStack(spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(text)
                .readoutValue(size: 36)
                .monospacedDigit()
                .foregroundStyle(isLevel ? Color.green : Color.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(ValueFormatting.decimal(value, digits: 1)) degrees")
    }

    private func controls(gravity: Vector3, isSurface: Bool) -> some View {
        InstrumentControls {
            Button(isHeld ? "Release" : "Hold", systemImage: isHeld ? "play.fill" : "pause.fill") {
                withReadoutAnimation {
                    frozen = isHeld ? nil : hub.gravity
                }
            }
            .contentTransition(.symbolEffect(.replace))
            .accessibilityHint(isHeld ? "Lets the level follow the phone again" : "Freezes the reading")

            // Taken from the gravity on screen, so zeroing a held reading zeroes what was
            // being looked at rather than wherever the phone has moved to since.
            Button("Zero", systemImage: "scope") {
                withReadoutAnimation { settings.levelZero.zero(at: gravity) }
            }
            .accessibilityHint("Takes this position as level, for \(isSurface ? "lying flat" : "this edge")")

            if isZeroed(gravity, isSurface: isSurface) {
                Button("Clear zero", systemImage: "xmark.circle") {
                    withReadoutAnimation { settings.levelZero.clear(at: gravity) }
                }
                .transition(.blurReplace)
            }
        }
    }
}

/// The circular vial, for a phone lying flat.
private struct SurfaceVial: View {
    /// Where the bubble sits, as a fraction of the vial's usable radius.
    let offset: CGSize
    let isLevel: Bool
    let namespace: Namespace.ID

    private static let bubbleSize: CGFloat = 46

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            let travel = size / 2 - Self.bubbleSize / 2 - 6

            ZStack {
                Circle()
                    .fill(.white.opacity(0.04))
                Circle()
                    .strokeBorder(isLevel ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), lineWidth: isLevel ? 2 : 1.5)

                // Rings at 5° and 10°; the rim is 15°, as far as the bubble goes (R-32).
                ForEach([1.0 / 3, 2.0 / 3], id: \.self) { fraction in
                    Circle()
                        .stroke(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .frame(width: travel * 2 * fraction + Self.bubbleSize, height: travel * 2 * fraction + Self.bubbleSize)
                }
                Circle()
                    .stroke(isLevel ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary), lineWidth: 1.5)
                    .frame(width: Self.bubbleSize + 8, height: Self.bubbleSize + 8)
                Crosshair()
                    .stroke(.tertiary, lineWidth: 1)
                    .frame(width: size, height: size)

                LevelPulse(isLevel: isLevel, diameter: Self.bubbleSize + 8)

                Bubble(isLevel: isLevel, width: Self.bubbleSize, height: Self.bubbleSize)
                    .matchedGeometryEffect(id: "bubble", in: namespace)
                    .offset(x: offset.width * travel, y: offset.height * travel)
                    .motion(.readoutFollow, value: offset)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .padding(.horizontal, 8)
        .accessibilityHidden(true)
    }
}

/// The tube, for a phone standing on an edge. Turned to lie level in the world whichever
/// edge the phone is on, so the bubble moves the way the eye expects.
private struct EdgeVial: View {
    /// Along the tube, as a fraction of its travel; positive towards its right-hand end.
    let offset: Double
    let quarterTurns: Int
    let isLevel: Bool
    let namespace: Namespace.ID

    var body: some View {
        GeometryReader { geometry in
            let length = min(geometry.size.width, geometry.size.height) - 24
            let travel = length / 2 - 40

            ZStack {
                Capsule()
                    .fill(.white.opacity(0.04))
                    .overlay(Capsule().strokeBorder(isLevel ? AnyShapeStyle(Color.green) : AnyShapeStyle(.quaternary), lineWidth: 1.5))
                    .frame(width: length, height: 64)
                HStack(spacing: 60) {
                    Rectangle().frame(width: 1.5, height: 64)
                    Rectangle().frame(width: 1.5, height: 64)
                }
                .foregroundStyle(isLevel ? AnyShapeStyle(Color.green) : AnyShapeStyle(.tertiary))

                Bubble(isLevel: isLevel, width: 56, height: 40)
                    .matchedGeometryEffect(id: "bubble", in: namespace)
                    .offset(x: offset * travel)
                    .motion(.readoutFollow, value: offset)
            }
            .rotationEffect(.degrees(Double(-quarterTurns) * 90))
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .frame(height: quarterTurns.isMultiple(of: 2) ? 160 : 340)
        .motion(.readoutSmooth, value: quarterTurns)
        .accessibilityHidden(true)
    }
}

/// The bubble itself: lit from the top left like a real one, green once it is level.
private struct Bubble: View {
    let isLevel: Bool
    let width: CGFloat
    let height: CGFloat

    @Environment(\.themeAccent) private var accent

    var body: some View {
        let tint = isLevel ? Color.green : accent
        Capsule()
            .fill(RadialGradient(
                colors: [tint.opacity(0.95), tint.opacity(0.55)],
                center: UnitPoint(x: 0.35, y: 0.3),
                startRadius: 1,
                endRadius: max(width, height) * 0.7
            ))
            .overlay(alignment: .topLeading) {
                // The highlight, the detail that makes it read as a bubble rather than a dot.
                Ellipse()
                    .fill(.white.opacity(0.6))
                    .frame(width: width * 0.32, height: height * 0.2)
                    .blur(radius: 1.2)
                    .offset(x: width * 0.2, y: height * 0.16)
            }
            .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .frame(width: width, height: height)
            .shadow(color: tint.opacity(isLevel ? 0.6 : 0.35), radius: isLevel ? 12 : 6)
            .motion(.readoutSnappy, value: isLevel)
    }
}

/// One ring that swells out from the centre as the level is reached.
private struct LevelPulse: View {
    let isLevel: Bool
    let diameter: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .stroke(Color.green, lineWidth: 2)
            .frame(width: diameter, height: diameter)
            // Rest, then appear at full strength, then swell and fade. Only on the way into
            // level; leaving it is not an event worth marking.
            .phaseAnimator([0, 1, 2], trigger: isLevel) { ring, phase in
                ring
                    .scaleEffect(phase == 2 ? 2.2 : 1)
                    .opacity(phase == 1 && isLevel && !reduceMotion ? 0.8 : 0)
            } animation: { phase in
                phase == 2 ? .easeOut(duration: 0.7) : nil
            }
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let arm: CGFloat = 12
        path.move(to: CGPoint(x: rect.midX - arm, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX + arm, y: rect.midY))
        path.move(to: CGPoint(x: rect.midX, y: rect.midY - arm))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.midY + arm))
        return path
    }
}
