import AVFoundation
import Foundation

/// Sound level from microphone metering. Audio is read in memory to derive a level and is
/// never written anywhere (R-34, R-56).
@MainActor
@Observable
final class AudioLevelProvider: SensorProvider {
    let readings: Set<ReadingID> = [.soundLevel]
    var output: ((ReadingID, SensorSample) -> Void)?

    /// Added to every reading, from Settings (R-66).
    var calibrationOffset: Double = 0
    /// Fast response follows transients; slow response averages them out (R-34).
    var respondsFast = true {
        didSet { meter.timeConstant = respondsFast ? 0.125 : 1.0 }
    }

    private(set) var peak: Double = 0

    private let engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var timer: Timer?
    private var isRunning = false

    func isSupported(_ reading: ReadingID) -> Bool {
        !AVAudioSession.sharedInstance().availableInputs.isNilOrEmpty
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard reading == .soundLevel, !isRunning else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            // Measurement mode turns off the automatic gain that would distort a level reading.
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { return }
            let meter = meter
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                meter.consume(buffer)
            }
            engine.prepare()
            try engine.start()
            isRunning = true
            startPublishing()
        } catch {
            stop(reading)
        }
    }

    func stop(_ reading: ReadingID) {
        guard reading == .soundLevel else { return }
        timer?.invalidate()
        timer = nil
        if isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        isRunning = false
        meter.reset()
        peak = 0
    }

    func resetPeak() {
        peak = 0
        meter.reset()
    }

    private func startPublishing() {
        let interval = 1.0 / 10
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.publish()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func publish() {
        guard isRunning else { return }
        let rms = meter.smoothedRMS
        let decibels = SoundLevelMaths.decibels(rms: rms, calibrationOffset: calibrationOffset)
        peak = max(peak, decibels)
        output?(.soundLevel, SensorSample(values: [decibels], note: "Estimate"))
    }
}

/// Bridges the audio thread and the main actor: the tap writes, the timer reads.
private final class LevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var smoothed: Double = 0
    private var constant: TimeInterval = 0.125

    var timeConstant: TimeInterval {
        get { lock.withLock { constant } }
        set { lock.withLock { constant = newValue } }
    }

    var smoothedRMS: Double {
        lock.withLock { smoothed }
    }

    func reset() {
        lock.withLock { smoothed = 0 }
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Double = 0
        for index in 0..<count {
            let sample = Double(channel[index])
            sum += sample * sample
        }
        let rms = sqrt(sum / Double(count))
        let interval = Double(count) / buffer.format.sampleRate
        lock.withLock {
            let alpha = SoundLevelMaths.smoothing(timeConstant: constant, interval: interval)
            smoothed += alpha * (rms - smoothed)
        }
    }
}

private extension Optional where Wrapped == [AVAudioSessionPortDescription] {
    var isNilOrEmpty: Bool {
        self?.isEmpty ?? true
    }
}
