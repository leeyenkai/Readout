import AVFoundation
import Foundation

/// Light, estimated from the camera's exposure settings.
///
/// No frame is ever read, shown on the grid or written to disk: the capture session exists so
/// that the camera meters the scene, and Readout reads only ISO, shutter and aperture
/// (R-9, R-11, R-12, R-67).
@MainActor
@Observable
final class LightProvider: SensorProvider {
    let readings: Set<ReadingID> = [.light]
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Multiplier from Settings, until per-model calibration exists (R-10).
    var calibration: Double = 1 {
        didSet { source.calibration = calibration }
    }

    var position: AVCaptureDevice.Position = .back {
        didSet {
            guard position != oldValue, isRunning else { return }
            source.stop()
            source.start(position: position)
        }
    }

    /// Exposed so the Light Meter tool can show a preview of what is being metered (R-35).
    var captureSession: AVCaptureSession { source.session }

    private let source = CameraLightSource()
    private var isRunning = false

    init() {
        source.onLux = { [weak self] lux in
            Task { @MainActor [weak self] in
                self?.output?(.light, SensorSample(values: [lux], note: "Camera estimate"))
            }
        }
    }

    func isSupported(_ reading: ReadingID) -> Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard reading == .light, !isRunning else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else { return }
        isRunning = true
        source.calibration = calibration
        source.start(position: position)
    }

    func stop(_ reading: ReadingID) {
        guard reading == .light else { return }
        isRunning = false
        source.stop()
    }

    /// Meters a spot the user tapped, in the camera's own coordinate space (R-35).
    func meter(at point: CGPoint) {
        source.meter(at: point)
    }
}

/// Owns the capture session on its own serial queue, as AVFoundation expects, and reports a
/// lux estimate a few times a second.
private final class CameraLightSource: @unchecked Sendable {
    let session = AVCaptureSession()

    var onLux: (@Sendable (Double) -> Void)?
    var calibration: Double {
        get { lock.withLock { storedCalibration } }
        set { lock.withLock { storedCalibration = newValue } }
    }

    private let queue = DispatchQueue(label: "com.leeyenkai.Readout.camera")
    private let lock = NSLock()
    private var storedCalibration: Double = 1
    private var device: AVCaptureDevice?
    private var timer: DispatchSourceTimer?

    func start(position: AVCaptureDevice.Position) {
        queue.async { [self] in
            guard !session.isRunning else { return }
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
                  let input = try? AVCaptureDeviceInput(device: device) else { return }

            session.beginConfiguration()
            // The lowest preset that still meters: Readout needs exposure data, not pixels.
            session.sessionPreset = .low
            session.inputs.forEach(session.removeInput)
            if session.canAddInput(input) { session.addInput(input) }
            if session.outputs.isEmpty {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                // No delegate is set, so no frame is ever delivered to Readout.
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            session.commitConfiguration()

            self.device = device
            session.startRunning()
            scheduleSampling()
        }
    }

    func stop() {
        queue.async { [self] in
            timer?.cancel()
            timer = nil
            if session.isRunning { session.stopRunning() }
            device = nil
        }
    }

    func meter(at point: CGPoint) {
        queue.async { [self] in
            guard let device, device.isExposurePointOfInterestSupported else { return }
            guard (try? device.lockForConfiguration()) != nil else { return }
            device.exposurePointOfInterest = point
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            device.unlockForConfiguration()
        }
    }

    private func scheduleSampling() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.2, repeating: 0.2)
        timer.setEventHandler { [weak self] in
            self?.sample()
        }
        timer.resume()
        self.timer = timer
    }

    private func sample() {
        guard let device, session.isRunning else { return }
        let duration = CMTimeGetSeconds(device.exposureDuration)
        guard let lux = LightMaths.lux(
            aperture: Double(device.lensAperture),
            exposureDuration: duration,
            iso: Double(device.iso),
            calibration: calibration
        ) else { return }
        onLux?(lux)
    }
}
