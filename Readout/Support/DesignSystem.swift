import SwiftUI

/// The measurements every screen is built from, so a card on one screen is the same card on
/// the next (R-46).
///
/// Before these existed the same kind of glass card had been given radii of 18, 20, 22 and 24
/// and paddings of 12, 14, 16 and 20, depending on which screen it was written for.
enum Metrics {
    /// A glass card: a panel of readings, an explainer, a tool's readout.
    static let cardRadius: CGFloat = 24
    /// A tile on the readings grid, which is smaller and sits closer to its neighbours.
    static let tileRadius: CGFloat = 20
    /// Something clipped inside a card: a camera preview, a route, the 3D stage.
    static let insetRadius: CGFloat = 18
    static let cardPadding: CGFloat = 16
    /// The gap down the side of every screen.
    static let screenPadding: CGFloat = 16
    /// Between the cards of a screen.
    static let stackSpacing: CGFloat = 16
    /// Room under a screen's last card, so it clears the tab bar and the recording bar.
    static let bottomPadding: CGFloat = 32
}

extension View {
    /// A glass card at the standard padding and radius, as wide as the screen allows.
    func readoutCard(padding: CGFloat = Metrics.cardPadding, alignment: Alignment = .leading) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: alignment)
            .glassEffect(.regular, in: .rect(cornerRadius: Metrics.cardRadius))
    }
}

/// The scroll view, spacing, margins and theme every full screen sits in.
///
/// Every tool, detail view and recording uses it, so they scroll the same way, clear the tab
/// bar by the same amount, and none of them is left without a scroll view to fall back on
/// when the text is made large (R-52).
struct ReadoutScreen<Content: View>: View {
    var spacing: CGFloat = Metrics.stackSpacing
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: spacing) {
                content
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.bottom, Metrics.bottomPadding)
        }
        .scrollIndicators(.hidden)
        .themedSurface()
    }
}

/// A card's heading: what the card is, with an optional symbol and something on the right —
/// a count, a Reset button.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            trailing
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil) {
        self.init(title: title, symbol: symbol) { EmptyView() }
    }
}

/// A small capsule that says something is so: Held, Zeroed, Simulated.
struct StatusBadge: View {
    let text: String
    let symbol: String
    var tint: Color?

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.tint))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .transition(.blurReplace.combined(with: .scale(0.85)))
    }
}

/// What every screen shows while the first value is on its way.
struct WaitingLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .accessibilityElement(children: .combine)
    }
}

/// An instrument's row of actions — Hold, Zero, Reset, Calibrate — centred, wrapping when
/// the text is large, every button the same glass style and every label an action rather
/// than a state (R-52).
struct InstrumentControls<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowRow(spacing: 10, alignment: .center) {
            content
        }
        .buttonStyle(.glass)
        .font(.subheadline.weight(.medium))
        .frame(maxWidth: .infinity)
    }
}

/// One figure of a min / max / average row: the label above, the number below.
struct StatColumn: View {
    let label: String
    let text: String
    let spoken: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(spoken)")
    }
}

/// Press feedback for a card that is a button or a link: it gives a little under the finger.
///
/// Used in place of interactive glass on the tiles and tool rows. Interactive glass handles
/// the touch itself, and inside a navigation link it could take the tap without the link
/// ever seeing it — the row lit up and nothing opened.
struct PressableCardStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(reduceMotion ? nil : .readoutSnappy, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableCardStyle {
    static var pressableCard: PressableCardStyle { PressableCardStyle() }
}
