import SwiftUI

/// Puts the chosen theme and interface size onto the app (R-77, R-78).
///
/// Applied once at the root, for the two things a sheet inherits by itself: the tint and the
/// accent colour. Everything a presentation does *not* inherit lives in `ThemedSurface`,
/// which every screen applies for itself.
struct Themed: ViewModifier {
    @Environment(AppSettings.self) private var settings

    func body(content: Content) -> some View {
        let theme = settings.theme
        content
            .modifier(ThemedSurface())
            .tint(theme.accent)
            // For the handful of places a ShapeStyle will not do: Swift Charts series
            // colours and the tile sparklines, which need a concrete `Color`.
            .environment(\.themeAccent, theme.accent)
    }
}

/// The parts of a theme a presentation does not inherit from the view that put it up: a sheet
/// gets the system's grouped background and the window's own appearance whatever the screen
/// behind it is wearing, and its own interface size.
///
/// **Apply it inside the `NavigationStack`, on the screen's own scroll view or form — never
/// to the stack itself.** A `NavigationStack` paints an opaque system background behind its
/// content, so a backdrop placed behind the stack is drawn and then covered, and the theme
/// silently does nothing. For the same reason a pushed screen does not inherit it: every
/// screen dresses itself, which is the one thing to remember when adding one.
///
/// Applying it twice is harmless. That is what `systemTypeSize` is for: the interface size is
/// a *step away from* the size the phone is set to, so a second application that could only
/// see the already-stepped size would step again and compound. The unstepped size is carried
/// alongside instead, and every application lands on the same answer.
struct ThemedSurface: ViewModifier {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dynamicTypeSize) private var inheritedTypeSize
    @Environment(\.systemTypeSize) private var systemTypeSize

    func body(content: Content) -> some View {
        // The first application is the one that sees the phone's own setting.
        let base = systemTypeSize ?? inheritedTypeSize
        content
            // Form and List paint an opaque grouped background that would cover the
            // backdrop completely.
            .scrollContentBackground(.hidden)
            .background {
                ThemeBackdrop(theme: settings.theme).ignoresSafeArea()
            }
            .preferredColorScheme(settings.theme.colourScheme)
            .environment(\.systemTypeSize, base)
            .dynamicTypeSize(settings.interfaceScale.applied(to: base))
    }
}

extension View {
    /// Dresses the whole app in the current theme and interface size. Root only.
    func themed() -> some View {
        modifier(Themed())
    }

    /// Puts the theme's backdrop behind a sheet, which inherits everything else.
    func themedSurface() -> some View {
        modifier(ThemedSurface())
    }
}

/// The colour a theme puts behind the content. Every glass surface in the app takes its own
/// tint from this, which is how one gradient re-colours the whole interface (R-46, R-77).
struct ThemeBackdrop: View {
    let theme: AppTheme

    var body: some View {
        switch theme.backdrop.count {
        case 0:
            // `.system` leaves iOS to draw its own background, so dark mode behaves exactly
            // as it did before themes existed.
            Color(.systemBackground)
        case 1:
            theme.backdrop[0]
        default:
            LinearGradient(colors: theme.backdrop, startPoint: .top, endPoint: .bottom)
        }
    }
}

extension EnvironmentValues {
    /// The text size the phone itself is set to, captured before the interface size stepped
    /// away from it (R-78). Nil until the first `ThemedSurface` records it.
    @Entry var systemTypeSize: DynamicTypeSize?

    /// The current theme's accent as a concrete colour.
    ///
    /// Most places want `.tint`, which resolves from the environment on its own. Swift Charts
    /// series colours and the sparkline stroke need a `Color`, and `Color.accentColor` reads
    /// the asset catalogue rather than the theme — so it would stay blue whatever was chosen.
    @Entry var themeAccent: Color = .accentColor
}

/// A large numeric readout: the dB figure on the Sound meter, the heading on the compass, the
/// value at the top of a detail view.
///
/// `size` is the point size at the default text size. These were written as a plain
/// `.font(.system(size:))`, which does not follow Dynamic Type at all — so the one number a
/// reading exists to show was the only thing on screen that did not grow with the text size,
/// and did not move when the interface size changed either (R-52, R-78).
///
/// The growth is capped: the type scale reaches about two and a half times its default at the
/// accessibility sizes, and a 64-point figure has nowhere to go. Past the cap the size holds
/// and the `minimumScaleFactor` already on these labels keeps the number on one line.
struct ReadoutValueFont: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight

    @ScaledMetric(relativeTo: .largeTitle) private var typeScale: CGFloat = 1

    /// Beyond this a readout crowds everything else off the screen.
    private static let maximumGrowth: CGFloat = 1.6

    func body(content: Content) -> some View {
        content.font(.system(
            size: size * min(typeScale, Self.maximumGrowth),
            weight: weight,
            design: .rounded
        ))
    }
}

extension View {
    /// A large rounded numeric readout that follows Dynamic Type and the interface size.
    func readoutValue(size: CGFloat, weight: Font.Weight = .semibold) -> some View {
        modifier(ReadoutValueFont(size: size, weight: weight))
    }
}
