import Testing
@testable import Readout

/// `SensorHub`'s activation bookkeeping — the thing that decides whether the microphone and
/// camera are still running after the user has walked away (R-64).
///
/// It had no coverage at all, and two defects: a tool that activated twice never reached zero,
/// and a `deactivate` passing a rate it had not asked for silently did nothing.
@MainActor
@Suite("Sensor leases")
struct SensorLeaseTests {
    private func makeHub() -> SensorHub {
        SensorHub(settings: AppSettings(defaults: throwawayDefaults()))
    }

    @Test("A reading stops once its only lease is given back")
    func singleLease() {
        let hub = makeHub()
        let lease = hub.activate(.acceleration)
        #expect(hub.isActive(.acceleration))

        hub.release(lease)
        #expect(!hub.isActive(.acceleration))
    }

    @Test("Two views holding the same reading keep it running until both let go")
    func twoLeases() {
        let hub = makeHub()
        let first = hub.activate(.acceleration)
        let second = hub.activate(.acceleration, rate: .display)

        hub.release(first)
        #expect(hub.isActive(.acceleration), "the second view is still looking at it")

        hub.release(second)
        #expect(!hub.isActive(.acceleration))
    }

    @Test("Releasing the same lease twice does not strand the reading")
    func doubleRelease() {
        let hub = makeHub()
        let first = hub.activate(.acceleration)
        let second = hub.activate(.acceleration)

        hub.release(first)
        hub.release(first)
        #expect(hub.isActive(.acceleration), "the second lease is still outstanding")

        hub.release(second)
        #expect(!hub.isActive(.acceleration))
    }

    @Test("Releasing nothing does nothing")
    func releasingNil() {
        let hub = makeHub()
        let lease = hub.activate(.acceleration)
        hub.release(nil)
        #expect(hub.isActive(.acceleration))
        hub.release(lease)
        #expect(!hub.isActive(.acceleration))
    }

    @Test("A lease is specific to its reading")
    func leasesDoNotCross() {
        let hub = makeHub()
        let acceleration = hub.activate(.acceleration)
        let rotation = hub.activate(.rotationRate)

        hub.release(acceleration)
        #expect(!hub.isActive(.acceleration))
        #expect(hub.isActive(.rotationRate))

        hub.release(rotation)
        #expect(!hub.isActive(.rotationRate))
    }

    @Test("Suspending and resuming keeps every outstanding lease")
    func suspendResume() {
        let hub = makeHub()
        let lease = hub.activate(.acceleration)

        hub.suspend()
        #expect(!hub.isActive(.acceleration))

        hub.resume()
        #expect(hub.isActive(.acceleration), "the view never went away, so the reading comes back")

        hub.release(lease)
        #expect(!hub.isActive(.acceleration))
    }
}
