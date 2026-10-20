import Foundation

/// Whether a recording can carry on once Readout is no longer in front, and when it cannot,
/// why (R-82).
///
/// iOS does not keep an app running because it would like to keep running. The only mechanism
/// that fits a sensor log is Core Location's background updates: an app with the `location`
/// background mode and `allowsBackgroundLocationUpdates` set stays alive for as long as it is
/// receiving fixes, with the blue indicator showing the whole time. Everything else the
/// session is recording then carries on too, not because each framework has a background mode
/// of its own, but because the process is never suspended.
///
/// That mechanism dictates the rules below, and the honest thing is to say so before a
/// recording starts rather than let somebody discover it at the end of a journey:
///
/// 1. **The microphone and the camera never run in the background.** Readout declares no
///    `audio` background mode and never will: a recording of a level is not a reason to let
///    an app listen with the screen off, and iOS terminates an app that holds the camera in
///    the background anyway. A session including Sound level or Light is foreground-only,
///    and no amount of location changes that (R-56, R-58).
/// 2. **Something has to be producing fixes.** Without a location reading there is no
///    background mode in force, so there is nothing keeping the app alive.
/// 3. **Location has to be allowed.** When In Use is enough — `allowsBackgroundLocationUpdates`
///    works with it, and shows the indicator — so Readout never asks for Always.
///
/// Pure, so the rules are covered by tests without a journey (AGENTS §5).
enum BackgroundRecording {
    /// The readings whose provider is what keeps the app alive: the ones that make Core
    /// Location deliver positions.
    ///
    /// Heading is deliberately not among them. `startUpdatingHeading()` does not hold an app
    /// in the background, and the location manager only starts delivering positions alongside
    /// it when true north is switched on — so a session recording heading alone would survive
    /// or not depending on a Settings toggle, which is no rule at all.
    static let sustainingReadings: Set<ReadingID> = [
        .coordinates, .gpsAltitude, .speed, .course, .locationAccuracy,
    ]

    /// The readings that must never run with nobody looking at the screen.
    static let foregroundOnlyReadings: Set<ReadingID> = [.soundLevel, .light]

    /// What will happen to a session when Readout leaves the foreground.
    enum Verdict: Equatable, Sendable {
        /// It keeps recording, with the blue location indicator showing.
        case continues
        /// It stops and saves, because it records the microphone or the camera.
        case stopsForSensitiveSensor(ReadingID)
        /// It stops and saves, because nothing in it produces location fixes.
        case stopsWithoutLocation
        /// It stops and saves, because location has not been allowed.
        case stopsWithoutPermission

        var continuesInBackground: Bool { self == .continues }
    }

    /// What will happen to a session recording `readings`.
    ///
    /// The sensitive-sensor rule is checked first because it is the only one that cannot be
    /// resolved: adding a location reading fixes the other two, and nothing fixes this one.
    static func verdict(for readings: some Collection<ReadingID>, isLocationGranted: Bool) -> Verdict {
        // In catalog order, so a session with both the microphone and the camera always names
        // the same one rather than whichever the set happened to iterate first.
        if let sensitive = ReadingCatalog.all.map(\.id)
            .first(where: { foregroundOnlyReadings.contains($0) && readings.contains($0) }) {
            return .stopsForSensitiveSensor(sensitive)
        }
        guard readings.contains(where: sustainingReadings.contains) else {
            return .stopsWithoutLocation
        }
        guard isLocationGranted else { return .stopsWithoutPermission }
        return .continues
    }
}

extension BackgroundRecording.Verdict {
    /// What the New Recording sheet says before the session starts, and the running session
    /// says while it runs.
    var summary: String {
        switch self {
        case .continues:
            """
            This session keeps recording if you lock the phone or switch apps. iOS shows the \
            blue location indicator for as long as it does.
            """
        case .stopsForSensitiveSensor(let reading):
            """
            \(ReadingCatalog.descriptor(reading).name) uses the \
            \(Self.sensorName(reading)), which Readout never runs while it is in the \
            background. This session stops and saves when you leave the app.
            """
        case .stopsWithoutLocation:
            """
            This session stops and saves when you leave the app. Add a location reading and \
            it will keep recording instead — that is what allows Readout to go on running.
            """
        case .stopsWithoutPermission:
            """
            This session stops and saves when you leave the app, because location has not \
            been allowed. Allow it and a session that records your position keeps recording.
            """
        }
    }

    /// The short line on the recording bar's own screen.
    var shortSummary: String {
        switch self {
        case .continues: "Keeps recording in the background"
        case .stopsForSensitiveSensor, .stopsWithoutLocation, .stopsWithoutPermission:
            "Stops if you leave Readout"
        }
    }

    var symbol: String {
        self == .continues ? "lock.iphone" : "iphone.gen3"
    }

    private static func sensorName(_ reading: ReadingID) -> String {
        reading == .soundLevel ? "microphone" : "camera"
    }
}
