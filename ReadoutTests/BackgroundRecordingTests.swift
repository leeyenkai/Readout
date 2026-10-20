import Foundation
import Testing
@testable import Readout

/// Which sessions may carry on once Readout is no longer in front, and which may not (R-82).
///
/// The rules exist because of how iOS keeps an app alive, not because of what would be
/// convenient, so each case here is really a check that the app is not about to promise
/// something the system will not do.
@Suite("Background recording")
struct BackgroundRecordingTests {
    private func verdict(
        _ readings: [ReadingID],
        locationGranted: Bool = true
    ) -> BackgroundRecording.Verdict {
        BackgroundRecording.verdict(for: readings, isLocationGranted: locationGranted)
    }

    // MARK: - What keeps a session alive

    @Test("A session recording a position carries on")
    func positionSustainsASession() {
        #expect(verdict([.coordinates]) == .continues)
        #expect(verdict([.coordinates, .acceleration, .thermalState]) == .continues)
    }

    @Test("Any of the position readings will do, because any of them starts the fixes")
    func everySustainingReading() {
        for reading in BackgroundRecording.sustainingReadings {
            #expect(verdict([reading]) == .continues, "\(reading.rawValue) should sustain a session")
        }
    }

    @Test("A session with nothing producing fixes stops")
    func noLocationMeansNoBackground() {
        #expect(verdict([.acceleration]) == .stopsWithoutLocation)
        #expect(verdict([.acceleration, .rotationRate, .battery]) == .stopsWithoutLocation)
        #expect(verdict([]) == .stopsWithoutLocation)
    }

    /// `startUpdatingHeading()` does not hold an app in the background, and whether the
    /// manager also starts delivering positions alongside it depends on the true-north
    /// setting — so a session recording heading alone would survive or not according to a
    /// Settings toggle, which is no rule at all.
    @Test("Heading alone is not enough to keep a session alive")
    func headingDoesNotSustain() {
        #expect(verdict([.heading]) == .stopsWithoutLocation)
        #expect(!BackgroundRecording.sustainingReadings.contains(.heading))
        // With a position alongside it, the session is sustained by the position.
        #expect(verdict([.heading, .coordinates]) == .continues)
    }

    @Test("Location has to have been allowed")
    func permissionIsRequired() {
        #expect(verdict([.coordinates], locationGranted: false) == .stopsWithoutPermission)
        #expect(verdict([.coordinates], locationGranted: true) == .continues)
    }

    // MARK: - What can never carry on

    /// Readout declares no `audio` background mode and never will: a recording of a level is
    /// not a reason to let an app listen with the screen off (R-56, R-58).
    @Test("The microphone and the camera keep a session in the foreground, whatever else it records")
    func sensitiveSensorsAreNeverUnattended() {
        #expect(verdict([.soundLevel]) == .stopsForSensitiveSensor(.soundLevel))
        #expect(verdict([.light]) == .stopsForSensitiveSensor(.light))
        // Adding location does not buy its way past this one.
        #expect(verdict([.coordinates, .soundLevel]) == .stopsForSensitiveSensor(.soundLevel))
        #expect(verdict([.coordinates, .light]) == .stopsForSensitiveSensor(.light))
    }

    /// The rule that cannot be resolved is reported first: adding a location reading fixes
    /// the other two, and nothing fixes this one, so naming it is the useful answer.
    @Test("A session blocked on more than one count names the one that cannot be fixed")
    func theUnfixableReasonWins() {
        #expect(verdict([.soundLevel, .acceleration]) == .stopsForSensitiveSensor(.soundLevel))
        #expect(verdict([.light], locationGranted: false) == .stopsForSensitiveSensor(.light))
    }

    @Test("A session with both names the same one every time")
    func sensitiveSensorIsReportedInCatalogOrder() {
        // Sound level comes before Light in the catalog, so the answer does not depend on
        // which way a Set happened to iterate.
        #expect(verdict([.light, .soundLevel]) == .stopsForSensitiveSensor(.soundLevel))
        #expect(verdict([.soundLevel, .light]) == .stopsForSensitiveSensor(.soundLevel))
    }

    // MARK: - What the user is told

    @Test("Only the continuing verdict says it continues")
    func continuesInBackground() {
        #expect(BackgroundRecording.Verdict.continues.continuesInBackground)
        #expect(!BackgroundRecording.Verdict.stopsWithoutLocation.continuesInBackground)
        #expect(!BackgroundRecording.Verdict.stopsWithoutPermission.continuesInBackground)
        #expect(!BackgroundRecording.Verdict.stopsForSensitiveSensor(.light).continuesInBackground)
    }

    @Test("Every verdict explains itself")
    func everyVerdictIsDescribed() {
        let verdicts: [BackgroundRecording.Verdict] = [
            .continues,
            .stopsWithoutLocation,
            .stopsWithoutPermission,
            .stopsForSensitiveSensor(.soundLevel),
            .stopsForSensitiveSensor(.light),
        ]
        for verdict in verdicts {
            #expect(!verdict.summary.isEmpty)
            #expect(!verdict.shortSummary.isEmpty)
            #expect(!verdict.symbol.isEmpty)
        }
    }

    /// The indicator is the user's only sign that an app is still following them, so the
    /// promise to show it belongs in the copy, not just in the entitlement (R-58).
    @Test("The continuing verdict says the location indicator will be showing")
    func continuingVerdictMentionsTheIndicator() {
        #expect(BackgroundRecording.Verdict.continues.summary.contains("indicator"))
    }

    @Test("A session told it will stop is told what to do about it")
    func theFixableReasonsSayHowToFixThem() {
        #expect(BackgroundRecording.Verdict.stopsWithoutLocation.summary.contains("Add a location reading"))
        #expect(BackgroundRecording.Verdict.stopsWithoutPermission.summary.contains("Allow it"))
        #expect(
            BackgroundRecording.Verdict.stopsForSensitiveSensor(.soundLevel).summary
                .contains("microphone")
        )
        #expect(
            BackgroundRecording.Verdict.stopsForSensitiveSensor(.light).summary
                .contains("camera")
        )
    }

    // MARK: - The entitlement behind it

    /// `allowsBackgroundLocationUpdates` raises if the background mode is not declared, so
    /// the bundle has to carry it. A build that drops it should lose the feature quietly
    /// rather than crash on the first long recording.
    @Test("The app declares the location background mode this all depends on")
    func backgroundModeIsDeclared() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        #expect(modes?.contains("location") == true)
    }

    /// The microphone and the camera have no background mode and must never acquire one;
    /// the verdict rules above are the policy, this is the entitlement that enforces it.
    @Test("No other background mode is declared")
    func noOtherBackgroundModes() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(Set(modes) == ["location"])
    }
}
