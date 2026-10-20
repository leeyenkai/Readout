# AGENTS.md

Working agreement for AI agents and humans in this repo. Read this before changing anything.
`CLAUDE.md` points here; this file is the single source of working instructions.

## 1. What this project is

**Readout** — a free, native iPhone app that shows the phone's built-in sensors as clear,
live readings, plus four instruments (spirit level, compass, sound meter, light meter).
Hobby project: no ads, no in-app purchases, no accounts, no network calls.

The spec is [`docs/SPEC.md`](docs/SPEC.md). It is the source of truth for scope and carries
stable requirement IDs (`R-nn`). Read the relevant section before implementing a feature.

## 2. Toolchain

| | |
| --- | --- |
| Language | Swift 6 language mode (built with the 6.4 toolchain; CI uses 6.3.3) |
| UI | SwiftUI + Observation (`@Observable`), Swift Charts |
| Min OS | iOS 26.0 (`IPHONEOS_DEPLOYMENT_TARGET`) |
| Built with | Xcode 27 locally. **Xcode 26 or later is enough** — the deployment target is iOS 26.0 and Liquid Glass is an iOS 26 API, so nothing needs the iOS 27 SDK. CI proves it on 26.6 |
| Dependencies | **none** — no SPM packages, no CocoaPods, no Carthage |

Adding a third-party dependency needs a decision recorded in `docs/SPEC.md` first.

## 3. Build and test

Build for the Simulator:

```bash
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'generic/platform=iOS Simulator' build
```

Run the unit tests, naming a simulator from `xcrun simctl list devices available`:

```bash
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'platform=iOS Simulator,name=Readout iPhone' test
```

To see the app, use the iOS Simulator tooling rather than describing the UI: attach the live
panel first, then build, install and launch, then take screenshots to verify.

**The project uses file-system-synchronized groups.** New Swift files inside `Readout/` or
`ReadoutTests/` are picked up automatically — never hand-edit `project.pbxproj` to add a file.

## 4. Layout

```
Readout/
├── .github/workflows/      CI: builds and runs the tests on every push
├── docs/SPEC.md            Specification (requirement IDs R-nn)
├── docs/RELEASE.md         What is done for release, and the on-device checklist
├── scripts/                screenshots.sh and other one-off tooling
├── Config/Info.plist       The one Info.plist key Xcode's generator cannot produce:
│                           UIBackgroundModes. Generated keys are merged on top of it
├── Readout/                App target
│   ├── App/                Entry point, root view, app-wide environment
│   ├── Model/              Reading catalog, values, units, comparison scales, calibration
│   ├── Sensors/            Sensor hub + one provider per framework
│   ├── Features/
│   │   ├── Readings/       Tile grid, tiles, detail view, chart, stats
│   │   ├── Tools/          Spirit level, compass, sound meter, light meter
│   │   ├── Recordings/     Recording and CSV export (v0.2), the live session view and
│   │   │                    the route panel (v0.5, R-76, R-79)
│   │   ├── Onboarding/     The one-time first-run explainer (v0.3)
│   │   └── Settings/       Settings sheet, stored preferences, calibration (R-75),
│   │                        themes and interface size (R-77, R-78)
│   ├── Support/            Theme and interface-size modifiers, haptics and other helpers
│   ├── AppIcon.icon/       Icon Composer document — open it in Icon Composer, not a text editor
│   ├── PrivacyInfo.xcprivacy
│   └── Assets.xcassets/
└── ReadoutTests/           Unit tests for pure logic
```

## 5. Architecture rules

1. **One hub, one manager.** `SensorHub` is the only owner of `CMMotionManager`,
   `CLLocationManager`, the audio session and the capture session (R-63). Views never create
   a manager. Add a new sensor by adding a provider, not by reaching for a framework in a view.
2. **Leased lifecycle.** Views take a lease — `let lease = hub.activate(_:)` in `.onAppear` —
   and give it back with `hub.release(lease)` in `.onDisappear`. A provider starts on the first
   lease and stops when the last one goes, or on backgrounding (R-64). Never leave a sensor
   running: a lease exists precisely because the old paired `activate`/`deactivate` calls were
   maintained by hand and left the microphone and camera on.
3. **Catalog-driven UI.** A reading's name, symbol, group, unit, permission, explainer and
   comparison scale live in `ReadingCatalog`. Adding a reading should mean adding a
   `ReadingDescriptor` and a provider — not a new view.
4. **`@MainActor` for anything observable.** Framework callbacks arrive off the main actor;
   hop with `MainActor.assumeIsolated` in a `nonisolated` delegate method, or `Task { @MainActor in }`.
   Keep `@Observable` state main-actor-isolated.
5. **Pure logic stays pure.** Unit conversion, dB/lux maths, statistics and formatting go in
   `Model/` as free functions or value types, so `ReadoutTests` can cover them without hardware.
6. **Availability before display.** Check hardware and permission state and hide or gate the
   reading; never show a dead tile (R-7, R-18–21).

## 6. Privacy — non-negotiable

- **No network.** No URLSession, no analytics, no crash reporting, no remote config. Readout
  makes no network request of its own, and nothing measured or recorded ever leaves the phone.
  If a change would make one, stop and raise it instead (R-59).
  - **The one exception, and it stays the only one:** showing a recorded route on Apple Maps
    makes iOS fetch map tiles. It is off by default, the default route view is a `Canvas` plot
    drawn from the session's own CSV, and the user turns it on from a dialog that says what the
    trade is (R-76, R-81). Adding a second exception is a spec decision, not a code change.
- **Settings must keep telling the truth about this.** The Privacy section names the state
  ("Network requests: None" / "Apple Maps only"), and the README, the Welcome sheet and
  `PrivacyInfo.xcprivacy` all make claims about it. A change here touches all of them.
- Microphone samples and camera frames are read in memory for levels only and never written to
  disk, never displayed as saved media (R-56).
- Never suppress or work around the system microphone/camera indicators, or the blue one shown
  while a recording runs in the background (R-58).
- **The microphone and the camera never run in the background.** `location` is the only
  `UIBackgroundModes` entry Readout declares, and a session recording Sound level or Light is
  foreground-only whatever else it records (R-83). Adding an `audio` background mode is a spec
  decision, not a code change; a test asserts `location` is the only mode in the bundle.
- Background location is set only while a qualifying recording runs and cleared the moment it
  stops, and Readout asks for When In Use, never Always (R-82, R-84).
- No new `Info.plist` usage key without a matching line in `docs/SPEC.md` §10.

## 7. Conventions

- Swift API Design Guidelines. Types `UpperCamelCase`, members `lowerCamelCase`, no `m_` or `_`
  prefixes for stored properties.
- One primary type per file, named after the file.
- British English in user-facing copy and comments ("metre", "colour", "calibrate"), matching
  the spec. Exception: Apple API names and `Measurement` unit symbols stay as Apple spells them.
- Comments explain *why*, not *what*. Match the density of the surrounding file.
- Every user-facing string is a plain literal for now; there is no localisation layer yet
  (R-53 — English at launch).
- Numbers shown to the user go through `Model/ValueFormatting.swift`, never raw
  `String(format:)` in a view.

## 8. Changes and releases

- Warnings are errors (`SWIFT_TREAT_WARNINGS_AS_ERRORS`). A change that introduces one does
  not build.
- **`CHANGELOG.md` is updated in the same change as the code.** Keep a Changelog format,
  Semantic Versioning. Put entries under `## [Unreleased]` and cite requirement IDs where
  one applies, for example `- Sound meter now warns at 85 dB (R-34).`
- When a release is cut, move `[Unreleased]` to a version heading with a date, and update the
  milestone table in `docs/SPEC.md` §12.
- **Keep `docs/SPEC.md` honest.** If a feature lands, or lands only partly, change its status in
  the same commit. Do not mark something Done that has not been verified to work.
- Commit messages: imperative mood, a short subject line, body explaining why where it is not
  obvious. Reference requirement IDs when a commit implements one.
- Do not commit or push unless asked.

## 9. Known constraints

- **The Simulator has no sensors.** `SensorHub` takes *every* reading from `MockSensorSource`
  there — not only the ones a framework admits to lacking, because Core Location reports itself
  available and then never produces a fix. The UI is demoable and every value says "Simulated",
  but any claim about a real reading needs a physical iPhone (R-71).
- Sound (dB) and light (lux) figures are estimates from level metering and camera exposure.
  They must always be shown with "≈" or an "estimate" note. A user can correct them against a
  reference meter (R-75); the per-model baseline table stays empty until models are measured
  (R-72).
- iOS exposes no ambient-light and no temperature API. Do not add an "air temperature" reading;
  Thermal State is about the phone, not the room (R-13, R-14, X-2).
