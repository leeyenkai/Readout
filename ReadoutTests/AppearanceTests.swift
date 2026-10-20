import Foundation
import SwiftUI
import Testing
@testable import Readout

/// Themes and interface size: the parts that are arithmetic or persistence rather than
/// colour, which is all a test can honestly hold an opinion about (R-77, R-78).
@MainActor
@Suite("Appearance")
struct AppearanceTests {
    // MARK: - Themes

    @Test("Every theme identifier has a theme, and no identifier is used twice")
    func catalogIsComplete() {
        let ids = ThemeCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(Set(ids) == Set(ThemeID.allCases))
        for id in ThemeID.allCases {
            #expect(ThemeCatalog.theme(id).id == id)
        }
    }

    @Test("System is the default and the only one that leaves the appearance alone")
    func systemFollowsThePhone() {
        #expect(ThemeCatalog.all.first?.id == .system)
        #expect(ThemeCatalog.theme(.system).colourScheme == nil)
        #expect(ThemeCatalog.theme(.system).backdrop.isEmpty)
        for theme in ThemeCatalog.all where theme.id != .system {
            #expect(theme.colourScheme != nil, "\(theme.name) should choose an appearance")
            #expect(!theme.backdrop.isEmpty, "\(theme.name) should have a backdrop")
        }
    }

    @Test("Every theme has copy to show in the picker")
    func everyThemeIsDescribed() {
        for theme in ThemeCatalog.all {
            #expect(!theme.name.isEmpty)
            #expect(!theme.detail.isEmpty)
        }
    }

    @Test("A theme survives a new AppSettings reading the same defaults")
    func themePersists() {
        let defaults = throwawayDefaults()
        let settings = AppSettings(defaults: defaults)
        #expect(settings.themeIdentifier == .system)

        settings.themeIdentifier = .midnightBlue
        settings.interfaceScale = .larger

        let reopened = AppSettings(defaults: defaults)
        #expect(reopened.themeIdentifier == .midnightBlue)
        #expect(reopened.theme.name == "Midnight blue")
        #expect(reopened.interfaceScale == .larger)
    }

    /// A theme a later version added and this one has never heard of should not take the app
    /// down, or leave it with no look at all.
    @Test("An unknown theme falls back to System rather than failing")
    func unknownThemeFallsBack() {
        let defaults = throwawayDefaults()
        defaults.set("aurora", forKey: "settings.theme")
        #expect(AppSettings(defaults: defaults).themeIdentifier == .system)
    }

    @Test("Resetting the appearance puts both settings back")
    func resetAppearance() {
        let settings = AppSettings(defaults: throwawayDefaults())
        #expect(!settings.hasAppearanceChanges)

        settings.themeIdentifier = .sand
        settings.interfaceScale = .small
        #expect(settings.hasAppearanceChanges)

        settings.resetAppearance()
        #expect(settings.themeIdentifier == .system)
        #expect(settings.interfaceScale == .default)
        #expect(!settings.hasAppearanceChanges)
    }

    // MARK: - Interface size

    @Test("The default size leaves the phone's own text size exactly as it is")
    func standardIsNeutral() {
        for size in DynamicTypeSize.allCases {
            #expect(InterfaceScale.standard.applied(to: size) == size)
        }
    }

    @Test("From the usual text size the control stops short of the accessibility sizes")
    func rangeFromTheDefault() {
        #expect(InterfaceScale.smaller.applied(to: .large) == .small)
        #expect(InterfaceScale.small.applied(to: .large) == .medium)
        #expect(InterfaceScale.large.applied(to: .large) == .xLarge)
        #expect(InterfaceScale.larger.applied(to: .large) == .xxLarge)
        #expect(InterfaceScale.largest.applied(to: .large) == .xxxLarge)
    }

    /// Somebody who has asked iOS for large text should get large text *and* whatever they
    /// pick here — the two compose rather than one overruling the other (R-52).
    @Test("It steps away from whatever the phone is set to, not from the default")
    func composesWithDynamicType() {
        #expect(InterfaceScale.large.applied(to: .xxLarge) == .xxxLarge)
        #expect(InterfaceScale.large.applied(to: .accessibility1) == .accessibility2)
        #expect(InterfaceScale.smaller.applied(to: .accessibility3) == .accessibility1)
    }

    @Test("Neither end of the type scale can be stepped past")
    func clampsAtBothEnds() {
        #expect(InterfaceScale.smaller.applied(to: .xSmall) == .xSmall)
        #expect(InterfaceScale.small.applied(to: .xSmall) == .xSmall)
        #expect(InterfaceScale.largest.applied(to: .accessibility5) == .accessibility5)
        #expect(InterfaceScale.largest.applied(to: .accessibility4) == .accessibility5)
    }

    @Test("Every size says how it sits against the phone's own setting")
    func everySizeIsDescribed() {
        for scale in InterfaceScale.allCases {
            #expect(!scale.title.isEmpty)
            #expect(scale.detail.contains("iOS Settings"))
        }
        #expect(InterfaceScale.small.detail.contains("1 step"))
        #expect(InterfaceScale.smaller.detail.contains("2 steps"))
        #expect(InterfaceScale.large.detail.contains("1 step"))
    }
}
