import AVFoundation
import SwiftUI

/// Approximate lux with a live preview, spot metering, a camera switch and hold to
/// freeze (R-35). No frame is ever saved (R-12).
struct LightMeterView: View {
    @Environment(SensorHub.self) private var hub
    @Environment(AppSettings.self) private var settings

    @State private var lease: SensorLease?
    @State private var isHeld = false
    @State private var frozen: Double?
    @State private var isFrontCamera = false
    @State private var isCalibrating = false

    private let descriptor = ReadingCatalog.descriptor(.light)

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                    if let comparisons = descriptor.comparisons {
                        ComparisonPanel(descriptor: descriptor, scale: comparisons, units: settings.displayUnits)
                    }
                    controls
                    Text("Worked out from the camera's exposure settings, because iOS keeps the ambient light sensor to itself. Nothing is photographed or saved.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Light meter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                RecordButton(readings: [.light])
            }
        }
        .onAppear { syncActivation() }
        .onDisappear {
            hub.release(lease)
            lease = nil
            hub.light.position = .back
        }
        .onChange(of: hub.availability(.light)) { _, _ in syncActivation() }
        .sheet(isPresented: $isCalibrating) {
            CalibrationSheet(target: .light)
        }
    }

    /// Starts the camera once the permission allows it, and never more than once. The card
    /// above only asks; this reacts to the answer. Activating from the card as well used to
    /// leave an unbalanced claim behind, so the camera kept running — indicator and all —
    /// long after the user had walked away from the tool (R-19, R-64).
    private func syncActivation() {
        guard hub.availability(.light).isUsable else { return }
        guard lease == nil else { return }
        lease = hub.activate(.light)
    }


    private var lux: Double? {
        frozen ?? hub.sample(.light)?.value(0)
    }

    private var reading: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(lux.map { "≈" + ValueFormatting.decimal($0, digits: 0) } ?? "—")
                    .font(.system(size: 58, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("lux")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            Text(isHeld ? "Held" : "Camera estimate")
                .font(.caption)
                .foregroundStyle(isHeld ? Color.accentColor : Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lux.map { "About \(ValueFormatting.decimal($0, digits: 0)) lux" } ?? "No reading")
    }

    private var preview: some View {
        CameraPreview(session: hub.light.captureSession) { point in
            hub.light.meter(at: point)
        }
        .frame(height: 220)
        .clipShape(.rect(cornerRadius: 22))
        .overlay(alignment: .bottomLeading) {
            Text("Tap to meter a spot")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: .capsule)
                .padding(10)
        }
        .accessibilityLabel("Camera preview. Tap to meter a spot.")
    }

    /// A wrapping row, so a third control and large Dynamic Type do not push each other off
    /// the screen (R-52).
    private var controls: some View {
        FlowRow(spacing: 10) {
            Button(isHeld ? "Release" : "Hold") {
                isHeld.toggle()
                frozen = isHeld ? hub.sample(.light)?.value(0) : nil
            }
            .buttonStyle(.glass)
            .accessibilityHint(isHeld ? "Lets the reading follow the camera again" : "Freezes the reading")

            Button(isFrontCamera ? "Front camera" : "Rear camera") {
                isFrontCamera.toggle()
                hub.light.position = isFrontCamera ? .front : .back
            }
            .buttonStyle(.glass)
            .accessibilityHint("Switches which camera meters the light")

            Button("Calibrate") { isCalibrating = true }
                .buttonStyle(.glass)
        }
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows what the camera is metering. A preview layer only — Readout never receives a frame.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    /// Gives the tapped point in the camera's own coordinate space.
    let onTap: (CGPoint) -> Void

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
        var onTap: ((CGPoint) -> Void)?

        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

        var previewLayer: AVCaptureVideoPreviewLayer {
            layer as! AVCaptureVideoPreviewLayer
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .secondarySystemBackground
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not used")
        }

        @objc private func handleTap(_ recogniser: UITapGestureRecognizer) {
            let point = recogniser.location(in: self)
            onTap?(previewLayer.captureDevicePointConverted(fromLayerPoint: point))
        }
    }
}
