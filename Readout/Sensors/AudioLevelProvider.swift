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

    /// What the microphone is actually doing. The Sound meter shows this rather than holding
    /// the last number on screen: a call or another app taking the microphone used to freeze
    /// the reading with no sign that it had stopped being true (P-2, R-34).
    private(set) var status: Status = .stopped

    enum Status: Equatable {
        case stopped
        case live
        /// Something else has the microphone — a call, Siri, another app.
        case interrupted
    }

    private var engine = AVAudioEngine()
    private let meter = LevelMeter()
    private var timer: Timer?
    private var isRunning = false
    /// Whether a view still wants the microphone, as distinct from whether it is running.
    /// An interruption stops the engine without clearing this, so the level comes back by
    /// itself when the call ends.
    private var isWanted = false
    /// Tracked separately from `isRunning`, because a tap installed before a throwing
    /// `engine.start()` is still installed. Removing it only when the engine was running
    /// left it behind, and the next `installTap` on the same bus traps inside AVFAudio.
    private var hasTap = false
    private var observers: [NSObjectProtocol] = []

    func isSupported(_ reading: ReadingID) -> Bool {
        !AVAudioSession.sharedInstance().availableInputs.isNilOrEmpty
    }

    func start(_ reading: ReadingID, rate: ActivationRate) {
        guard reading == .soundLevel, !isRunning else { return }
        guard AVAudioApplication.shared.recordPermission == .granted else { return }
        isWanted = true
        observeSessionEvents()
        startEngine()
    }

    func stop(_ reading: ReadingID) {
        guard reading == .soundLevel else { return }
        isWanted = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        teardown()
        status = .stopped
        peak = 0
    }

    func resetPeak() {
        peak = 0
        meter.reset()
    }

    // MARK: - Engine

    private func startEngine() {
        do {
            let session = AVAudioSession.sharedInstance()
            // Measurement mode turns off the automatic gain that would distort a level reading.
            try session.setCategory(.record, mode: .measurement, options: [])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else {
                teardown()
                status = .interrupted
                return
            }
            let meter = meter
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                meter.consume(buffer)
            }
            hasTap = true
            engine.prepare()
            try engine.start()
            isRunning = true
            status = .live
            startPublishing()
        } catch {
            // Routine: another app holds the microphone, or an interruption is still in force.
            teardown()
            status = .interrupted
        }
    }

    /// Returns the engine to a state `startEngine()` can be called from again.
    private func teardown() {
        timer?.invalidate()
        timer = nil
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        if engine.isRunning {
            engine.stop()
        }
        isRunning = false
        meter.reset()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func restart() {
        teardown()
        guard isWanted else { return }
        startEngine()
    }

    // MARK: - Session events

    private func observeSessionEvents() {
        guard observers.isEmpty else { return }
        let centre = NotificationCenter.default
        observers.append(centre.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Notification is not Sendable, so the two values that matter are read here and
            // only they cross to the main actor.
            let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            MainActor.assumeIsolated { self?.handleInterruption(type: type, options: options) }
        })
        // A headset or Bluetooth microphone arriving changes the hardware format, and a tap
        // installed with the old one asserts. Reinstall it against the new route.
        observers.append(centre.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleRouteChange() }
        })
        // The audio server died and took the engine with it; nothing survives but a new one.
        observers.append(centre.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleMediaServicesReset() }
        })
    }

    private func handleInterruption(type: UInt?, options: UInt?) {
        guard let type, let kind = AVAudioSession.InterruptionType(rawValue: type) else { return }
        switch kind {
        case .began:
            teardown()
            status = .interrupted
        case .ended:
            let resumable = AVAudioSession.InterruptionOptions(rawValue: options ?? 0)
            guard resumable.contains(.shouldResume) else { return }
            restart()
        @unknown default:
            restart()
        }
    }

    private func handleRouteChange() {
        guard isRunning else { return }
        restart()
    }

    private func handleMediaServicesReset() {
        teardown()
        engine = AVAudioEngine()
        guard isWanted else { return }
        startEngine()
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
        guard isRunning, status == .live else { return }
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
