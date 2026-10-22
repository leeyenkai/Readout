import AVFoundation
import SwiftUI

/// Approximate lux with a live preview, spot metering, a camera switch and hold to
/// freeze (R-35). No frame is ever saved (R-12).
struct LightMeterView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings
    @Environment(RecordingService.self) private var recorder

    @State private var lease: SensorLease?
    /// Leases are only ever taken while this is on screen. A tab switch hides the view without
    /// destroying it, and giving the lease back changes the availability this reacts to — so
    /// without the flag, leaving would start the camera again behind the user's back (R-64).
    @State private var isVisible = false
    @State private var frozen: Double?
    @State private var camera: AVCaptureDevice.Position = .back
    @State private var isCalibrating = false
    /// Where the user last tapped to meter, in the preview's own coordinates.
    @State private var spot: CGPoint?
    @State private var spotLanding = false
    /// Turns the preview over when the camera changes, so the switch reads as one.
    @State private var flipAngle: Double = 0

    private let descriptor = ReadingCatalog.descriptor(.light)

    var body: some View {
        ReadoutScreen {
            switch hub.availability(.light) {
            case .needsPermission(let permission):
                PermissionCard(permission: permission, isDenied: false) {
                    await hub.requestPermission(permission)
                }
            case .denied(let permission):
                PermissionCard(permission: permission, isDenied: true) {
                    hub.permissions.openSettings()
                }
            case .unavailable:
                UnavailableCard(name: "camera")
            case .live, .ready:
                reading
                preview
                controls
                if let comparisons = descriptor.comparisons {
                    ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
                }
                Text("Worked out from the camera's exposure settings, because iOS keeps the ambient light sensor to itself. Nothing is photographed or saved.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .navigationTitle("Light meter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.light])
            }
        }
        .onAppear {
            isVisible = true
            // A recording logging light keeps the camera it started on, which may be the front.
            camera = hub.light.position
            syncActivation()
        }
        .onDisappear {
            isVisible = false
            hub.release(lease)
            lease = nil
            // Back to the rear camera for next time — unless a recording is logging light, when
            // changing camera under it would change what its lux column measures (R-67).
            if !isRecordingLight {
                hub.light.position = .back
            }
        }
        .onChange(of: hub.availability(.light).isUsable) { _, _ in syncActivation() }
        .sheet(isPresented: $isCalibrating) {
            CalibrationSheet(target: .light)
        }
    }

    /// Starts the camera once the permission allows it, and never more than once. The card
    /// above only asks; this reacts to the answer. Activating from the card as well used to
    /// leave an unbalanced claim behind, so the camera kept running — indicator and all —
    /// long after the user had walked away from the tool (R-19, R-64).
    private func syncActivation() {
        guard isVisible, hub.availability(.light).isUsable else { return }
        guard lease == nil else { return }
        lease = hub.activate(.light)
    }

    private var interruption: String? { hub.stalledReason(.light) }

    private var lux: Double? {
        frozen ?? (interruption == nil ? hub.sample(.light)?.value(0) : nil)
    }

    private var reading: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(lux.map { "≈" + ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .readoutValue(size: 64)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("lux")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            Group {
                if frozen != nil {
                    StatusBadge(text: "Held", symbol: "pause.fill")
                } else if let interruption {
                    Label(interruption, systemImage: "pause.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(camera == .front ? "Front" : "Rear") camera estimate")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .transition(.blurReplace)
        }
        .motion(.readoutSnappy, value: frozen != nil)
        .readoutCard(padding: 20, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lux.map { "About \(ValueFormatting.decimal($0, digits: 0)) lux\(frozen != nil ? ", held" : "")" } ?? "No reading")
    }

    private var preview: some View {
        CameraPreview(session: hub.light.captureSession) { devicePoint, viewPoint in
            hub.light.meter(at: devicePoint)
            showSpot(at: viewPoint)
        }
        .frame(height: 230)
        .overlay {
            if !hub.light.isMetering {
                // An empty black panel looks broken. It is what the Simulator shows, which
                // has no camera to meter with — the reading above comes from the synthetic
                // source there (R-71).
                Label("No camera preview on this device", systemImage: "camera.metering.unknown")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if hub.light.isMetering {
                GeometryReader { geometry in
                    MeteringSpot(isLanding: spotLanding)
                        .position(spot ?? CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2))
                        .opacity(spot == nil ? 0.5 : 1)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if hub.light.isMetering {
                Text("Tap to meter a spot")
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .glassEffect(.regular, in: .capsule)
                    .padding(10)
            }
        }
        .background(.black.opacity(0.25))
        .clipShape(.rect(cornerRadius: Metrics.insetRadius))
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
        .padding(4)
        .glassEffect(.regular, in: .rect(cornerRadius: Metrics.insetRadius + 4))
        .accessibilityLabel("Camera preview. Tap to meter a spot.")
    }

    private func showSpot(at point: CGPoint) {
        spot = point
        spotLanding = true
        withReadoutAnimation(.readoutSpring) { spotLanding = false }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            InstrumentControls {
                Button(frozen == nil ? "Hold" : "Release", systemImage: frozen == nil ? "pause.fill" : "play.fill") {
                    withReadoutAnimation {
                        frozen = frozen == nil ? hub.sample(.light)?.value(0) : nil
                    }
                }
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHint(frozen == nil ? "Freezes the reading" : "Lets the reading follow the camera again")

                Button("Calibrate", systemImage: "slider.horizontal.3") { isCalibrating = true }
                    .disabled(isRecordingLight)
            }

            Picker("Camera", selection: Binding(
                get: { camera },
                set: { switchCamera(to: $0) }
            )) {
                Text("Rear camera").tag(AVCaptureDevice.Position.back)
                Text("Front camera").tag(AVCaptureDevice.Position.front)
            }
            .pickerStyle(.segmented)
            // The two cameras need separate calibration (R-67), so a recording's light column
            // stays with the one it started on.
            .disabled(isRecordingLight)

            if isRecordingLight {
                Text("The camera and calibration are fixed while a recording is logging light.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Turns the preview edge-on, changes camera while it cannot be seen, and turns it back —
    /// a half turn each way rather than a whole one, which would leave the preview mirrored.
    private func switchCamera(to position: AVCaptureDevice.Position) {
        guard position != camera else { return }
        camera = position
        spot = nil
        guard !UIAccessibility.isReduceMotionEnabled else {
            hub.light.position = position
            return
        }
        let direction: Double = position == .front ? 1 : -1
        withAnimation(.easeIn(duration: 0.18)) { flipAngle = 90 * direction }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            // Left mid-flip: the camera has already gone back to the rear for next time.
            guard isVisible else { return }
            hub.light.position = position
            flipAngle = -90 * direction
            withAnimation(.easeOut(duration: 0.24)) { flipAngle = 0 }
        }
    }

    private var isRecordingLight: Bool { recorder.isRecording(.light) }
}

/// Where the camera is metering: a square that lands with a spring where the user tapped,
/// as the Camera app's focus square does.
private struct MeteringSpot: View {
    let isLanding: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Color.yellow, lineWidth: 1.5)
            .frame(width: 64, height: 64)
            .overlay {
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 4, height: 4)
            }
            .scaleEffect(isLanding ? 1.45 : 1)
            .opacity(isLanding ? 0.4 : 1)
            .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

/// Shows what the camera is metering. A preview layer only — Readout never receives a frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Gives the tapped point in the camera's own coordinate space, and in the view's.
    let onTap: (CGPoint, CGPoint) -> Void

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.onTap = onTap
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.previewLayer.session = session
        view.onTap = onTap
    }

    final class PreviewView: UIView {
        var onTap: ((CGPoint, CGPoint) -> Void)?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            // Clear, so the card behind shows until the first frame arrives rather than a
            // grey panel that belongs to no theme.
            backgroundColor = .clear
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
            let point = recogniser.location(in: self)
            onTap?(previewLayer.captureDevicePointConverted(fromLayerPoint: point), point)
        }
    }
}
