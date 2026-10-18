import Foundation

/// Decides which of a provider's samples a recording keeps, so a session lands on the chosen
/// rate rather than on whatever the sensor happens to be running at (R-39, R-65).
///
/// A provider can be running faster than the recording asked for — a detail view wanting
/// display rate raises it for everyone — so the gate works from a grid of due times rather
/// than from the gap since the last sample. Keeping the grid is what makes 50 Hz out of a
/// 60 Hz stream come to 50 samples a second instead of 30.
struct SampleRateGate: Sendable {
    /// The shortest gap between kept samples. Zero keeps everything, which is what a
    /// native-cadence reading wants (R-39).
    let interval: TimeInterval

    private var due: Date?

    init(interval: TimeInterval) {
        self.interval = max(0, interval)
    }

    /// Location, air pressure and the pedometer keep every sample they are sent; everything
    /// else is held to the chosen rate, whether or not the recording can drive it (R-39).
    init(rate: RecordingRate, cadence: RecordingCadence) {
        switch cadence {
        case .driven, .capped: self.init(interval: rate.interval)
        case .free: self.init(interval: 0)
        }
    }

    /// Whether a sample arriving at `time` belongs in the recording. Mutating, because
    /// keeping one moves the grid on.
    mutating func accepts(_ time: Date) -> Bool {
        guard interval > 0 else { return true }
        guard let due else {
            self.due = time.addingTimeInterval(interval)
            return true
        }
        // A sensor running at exactly the requested rate still jitters by a millisecond or
        // two; without the tolerance every other sample would miss its slot. The cap keeps
        // the slack small in absolute terms, so 1 Hz stays 1 Hz rather than 1.1.
        let tolerance = min(interval * 0.1, 0.01)
        guard time.addingTimeInterval(tolerance) >= due else { return false }
        let lateness = time.timeIntervalSince(due)
        // More than a whole interval late means the sensor paused — a suspended app, a
        // location fix that took its time — so the grid restarts from here.
        self.due = lateness > interval
            ? time.addingTimeInterval(interval)
            : due.addingTimeInterval(interval)
        return true
    }
}
