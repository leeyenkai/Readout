import SwiftUI

/// Theme and interface size (R-77, R-78).
///
/// The screen is its own preview: it is drawn in the theme and at the size being chosen, so a
/// tap shows the result immediately rather than describing it.
struct AppearanceView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Form {
            Section {
                ForEach(ThemeCatalog.all) { theme in
                    ThemeRow(theme: theme, isChosen: theme.id == settings.themeIdentifier) {
                        withAnimation(.snappy) { settings.themeIdentifier = theme.id }
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("""
                    A theme sets the colour behind the readings and the accent on top of \
                    them. Everything else stays the system's own: the glass cards, the tab \
                    bar and the toolbars all take their tint from whatever is behind them. \
                    System follows your phone's Light and Dark setting; the rest choose for \
                    themselves.
                    """)
            }

            Section {
                Picker("Size", selection: Binding(
                    get: { settings.interfaceScale },
                    set: { settings.interfaceScale = $0 }
                )) {
                    ForEach(InterfaceScale.allCases) { scale in
                        Text(scale.title).tag(scale)
                    }
                }
                SizeSample()
            } header: {
                Text("Interface size")
            } footer: {
                Text("""
                    \(settings.interfaceScale.detail) It moves the whole app along the same \
                    scale iOS uses, so the tiles, the charts and the big readouts grow \
                    together and stay laid out properly. Set the text size itself in \
                    Settings › Display & Brightness, or turn on larger accessibility sizes \
                    there and this will follow them.
                    """)
            }

            if settings.hasAppearanceChanges {
                Section {
                    Button("Reset appearance", role: .destructive) {
                        withAnimation(.snappy) { settings.resetAppearance() }
                    }
                }
            }
        }
        .themedSurface()
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One theme in the list, shown as a strip of its own colours rather than a name alone.
private struct ThemeRow: View {
    let theme: AppTheme
    let isChosen: Bool
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            HStack(spacing: 14) {
                ThemeSwatch(theme: theme)

                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .foregroundStyle(.primary)
                    Text(theme.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Image(systemName: isChosen ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChosen ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            // Without this the gap between the name and the tick answers no taps.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? [.isSelected] : [])
        .accessibilityLabel(theme.name)
        .accessibilityValue(theme.detail)
    }
}

/// The theme's backdrop with its accent on top: what the tiles will look like, in miniature.
private struct ThemeSwatch: View {
    let theme: AppTheme

    var body: some View {
        ZStack {
            ThemeBackdrop(theme: theme)
            Circle()
                .fill(theme.accent)
                .frame(width: 12, height: 12)
                .offset(x: 7, y: 7)
        }
        .frame(width: 38, height: 38)
        .clipShape(.rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(.quaternary, lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// A line of real content at the chosen size, so the effect is visible without leaving the
/// screen — the figure is drawn by the same modifier the readings use.
private struct SizeSample: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("1,013.2")
                .readoutValue(size: 34)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text("hPa")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text("Sample")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Sample reading at the chosen size")
    }
}
