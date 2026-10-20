import SwiftUI

/// The themes Readout ships with (R-77).
///
/// Raw values are persisted, so they must not change once shipped. A theme removed from a
/// later version falls back to `.system` rather than leaving the app unthemed.
enum ThemeID: String, CaseIterable, Identifiable, Codable, Sendable {
    case system
    case dark
    case elegantBlue
    case midnightBlue
    case sand
    case graphite
    case forest

    var id: String { rawValue }
}

/// One look: the appearance it asks iOS for, the accent on top, and the colour the glass
/// sits over (R-77).
///
/// A theme deliberately changes only those three things. Liquid Glass takes its own colour
/// from whatever is behind it, so a tinted backdrop re-tints every card, tab bar and toolbar
/// in the app without any of them being redrawn by hand — which is what keeps this inside
/// Apple's design language rather than replacing it (R-46).
struct AppTheme: Identifiable, Sendable, Equatable {
    let id: ThemeID
    let name: String
    /// One line under the name in the picker, so a theme is more than a swatch.
    let detail: String
    /// The appearance to ask for, or nil to follow the phone's own Light/Dark setting.
    /// Honouring the system remains the default, so dark mode still works as it always did
    /// for anyone who never opens this screen (R-49).
    let colourScheme: ColorScheme?
    let accent: Color
    /// Top-to-bottom stops of the colour behind the content. Empty means the system's own
    /// background, which is what `.system` uses.
    let backdrop: [Color]

    /// Whether this theme's own appearance differs from the one the phone is set to, so the
    /// picker can say that choosing it overrides dark mode.
    var overridesSystemAppearance: Bool { colourScheme != nil }
}

/// The one place a theme is described, in the order the picker shows them.
enum ThemeCatalog {
    static let all: [AppTheme] = [
        AppTheme(
            id: .system,
            name: "System",
            detail: "Follows your phone's Light and Dark setting",
            colourScheme: nil,
            // The asset by name, not `Color.accentColor`: inside a `.tint()` the dynamic one
            // resolves to whatever tint is in force, which here is itself — so the System
            // swatch would show the colour of whichever theme was already chosen.
            accent: Color("AccentColor"),
            backdrop: []
        ),
        AppTheme(
            id: .dark,
            name: "Dark",
            detail: "Always dark, whatever the phone is set to",
            colourScheme: .dark,
            accent: Color(hex: 0x4C9AFF),
            backdrop: [Color(hex: 0x0B0B0D), Color(hex: 0x17171C)]
        ),
        AppTheme(
            id: .elegantBlue,
            name: "Elegant blue",
            detail: "A pale blue wash, light and quiet",
            colourScheme: .light,
            accent: Color(hex: 0x27508F),
            backdrop: [Color(hex: 0xBFD6F2), Color(hex: 0xEAF1FB)]
        ),
        AppTheme(
            id: .midnightBlue,
            name: "Midnight blue",
            detail: "Deep navy, for reading in the dark",
            colourScheme: .dark,
            accent: Color(hex: 0x7CB2FF),
            backdrop: [Color(hex: 0x070D1B), Color(hex: 0x132544)]
        ),
        AppTheme(
            id: .sand,
            name: "Sand",
            detail: "Warm paper, easy in daylight",
            colourScheme: .light,
            accent: Color(hex: 0x9A5A17),
            backdrop: [Color(hex: 0xE8D5B5), Color(hex: 0xF9F0E2)]
        ),
        AppTheme(
            id: .graphite,
            name: "Graphite",
            detail: "Neutral grey, nothing competing with the numbers",
            colourScheme: .dark,
            accent: Color(hex: 0x9AB0C6),
            backdrop: [Color(hex: 0x131517), Color(hex: 0x23272B)]
        ),
        AppTheme(
            id: .forest,
            name: "Forest",
            detail: "Dark green, for being outdoors with it",
            colourScheme: .dark,
            accent: Color(hex: 0x6CCF8A),
            backdrop: [Color(hex: 0x08140E), Color(hex: 0x13261B)]
        ),
    ]

    private static let index: [ThemeID: AppTheme] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    /// The theme for an identifier, falling back to `.system` rather than failing: a raw
    /// value read from a newer version's preferences is not worth refusing to launch over.
    static func theme(_ id: ThemeID) -> AppTheme {
        index[id] ?? all[0]
    }
}

extension Color {
    /// A colour from a packed `0xRRGGBB` literal, so the palette above reads as a palette.
    ///
    /// Theme colours are fixed values rather than asset-catalogue colours precisely because
    /// they must not adapt: a theme has already said which appearance it wants, and a
    /// backdrop that flipped underneath it would defeat the choice.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
