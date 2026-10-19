import Foundation
import Testing
@testable import Readout

/// The grid's saved arrangement (R-22).
@MainActor
@Suite("Tile order")
struct ReadingOrderTests {
    private func makeSettings() -> AppSettings {
        AppSettings(defaults: throwawayDefaults())
    }

    private let motion = ReadingCatalog.readings(in: .motion)

    @Test("With no arrangement saved, tiles stay in catalog order")
    func defaultsToCatalogOrder() {
        let settings = makeSettings()
        #expect(settings.ordered(motion).map(\.id) == motion.map(\.id))
    }

    @Test("Moving a tile puts it where the target was")
    func moveBefore() {
        let settings = makeSettings()
        let original = motion.map(\.id)
        let last = try! #require(original.last)
        let first = try! #require(original.first)

        settings.move(last, before: first)

        let moved = settings.ordered(motion).map(\.id)
        #expect(moved.first == last)
        #expect(moved.count == original.count)
        #expect(Set(moved) == Set(original), "reordering never loses or invents a tile")
    }

    @Test("The arrangement survives a new AppSettings reading the same defaults")
    func orderPersists() {
        let defaults = throwawayDefaults()
        let settings = AppSettings(defaults: defaults)
        let original = motion.map(\.id)
        settings.move(try! #require(original.last), before: try! #require(original.first))
        let expected = settings.ordered(motion).map(\.id)

        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.ordered(motion).map(\.id) == expected)
    }

    @Test("Resetting goes back to catalog order")
    func reset() {
        let settings = makeSettings()
        settings.move(try! #require(motion.last?.id), before: try! #require(motion.first?.id))
        settings.resetOrder()
        #expect(settings.ordered(motion).map(\.id) == motion.map(\.id))
    }

    @Test("A reading the saved arrangement has never seen still appears")
    func unknownReadingsSurvive() {
        let settings = makeSettings()
        // An arrangement saved before a reading existed — what an app update looks like.
        settings.readingOrder = [.heading, .acceleration]

        let ordered = settings.ordered(motion).map(\.id)
        #expect(ordered.prefix(2) == [.heading, .acceleration])
        #expect(Set(ordered) == Set(motion.map(\.id)), "nothing is dropped for being unlisted")
    }

    @Test("Moving a tile onto itself changes nothing")
    func moveOntoItself() {
        let settings = makeSettings()
        settings.move(.heading, before: .heading)
        #expect(settings.ordered(motion).map(\.id) == motion.map(\.id))
    }

    @Test("Hidden tiles are remembered separately from the order")
    func hidingIsIndependent() {
        let settings = makeSettings()
        settings.setHidden(true, for: .heading)
        settings.move(try! #require(motion.last?.id), before: try! #require(motion.first?.id))
        #expect(settings.isHidden(.heading))
        settings.showAllReadings()
        #expect(!settings.isHidden(.heading))
        #expect(settings.ordered(motion).count == motion.count)
    }
}
