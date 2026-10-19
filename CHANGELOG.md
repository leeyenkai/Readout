# Changelog

All notable changes to Readout are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). `R-nn` references point at
requirement IDs in [`docs/SPEC.md`](docs/SPEC.md).

## [Unreleased]

Nothing yet. The next milestone is **v1.0 — App Store**, and what it needs is on-device work:
see [`docs/RELEASE.md`](docs/RELEASE.md) §2.

## [0.3.0] — 2026-10-19

**Release readiness.** The app icon, the defects an audit of the whole source tree
turned up, the last of the `Partial` requirements, and the scaffolding an App Store submission
needs. Built and tested in the Simulator; the on-device pass that gates v1.0 is still outstanding
(`docs/RELEASE.md` §2).

### Added

- **App icon** — a rising trace with a live point, the same mark the tiles draw, as an Icon
  Composer document (`Readout/AppIcon.icon`). iOS 26 renders the default, dark, clear and
  tinted appearances from it, so the icon is Liquid Glass rather than a flat image (P-4, R-46).
- **First-run explainer** — a one-time sheet covering what Readout measures, that sound and
  light are estimates, and that nothing leaves the phone, shown before the first permission
  prompt (R-73).
- **Drag to reorder tiles** — the grid's arrangement is dragged in edit mode and saved on the
  device, with long-press as the other way in, a Reset order button, and VoiceOver move
  actions since VoiceOver cannot drag (R-22).
- **Chart audio graphs** — the live chart and every session chart expose an `AXChartDescriptor`,
  so VoiceOver can play the shape of a trace. The three axes also carry distinct dash patterns,
  so they are not told apart by colour alone (R-49, R-52).
- **Per-model calibration** — `DeviceCalibration` applies a per-iPhone sound offset and light
  multiplier underneath the user's own, keyed by hardware identifier. **The tables ship empty**:
  filling one in needs that model and a reference meter, and Settings says plainly that this
  iPhone has no measured baseline (R-10, R-66, R-72).
- **Recording limits** — a session stops itself at 100 MB or two hours, whichever comes first,
  warns in the bar from 80%, and refuses to start without the free space to finish. This
  settles **Q-4**, open since Draft 1 (R-40).
- **Crash recovery** — a running session writes a checkpoint beside its CSV files every two
  seconds, so a recording the app is killed during comes back on the next launch marked
  interrupted instead of being deleted as an orphan (R-41, R-57).
- **Privacy manifest** — `PrivacyInfo.xcprivacy` declaring no tracking, no collected data, and
  the two required-reason APIs the app uses: `UserDefaults` (CA92.1) and free-space checks
  (E174.1). Required for App Store upload, and it backs the "Data Not Collected" label (R-59).
- **Release scaffolding** — `docs/RELEASE.md` (what is done, and the on-device pass that still
  gates v1.0), `LICENSE` (MIT), a GitHub Actions workflow that builds and tests every push,
  `scripts/screenshots.sh`, and `ITSAppUsesNonExemptEncryption = NO` so export compliance is
  not asked on every upload.
- **Unit tests** — 30 more (109 in all), over sensor-lease reference counting, recording recovery and the
  file-deletion guard, the track writer and its failure path, the streaming CSV reader, tile
  ordering, non-finite coordinate formatting, and a channel appearing mid-session.

### Fixed

- **Every recording could be deleted on launch.** If SwiftData could not open its store, the
  app fell back to an empty in-memory one and then ran its tidy-up of files no session points
  at — which, against an empty store, is every recording on the device. The tidy-up now runs
  only against a store that really opened, never while recording, and never over a folder
  still carrying a checkpoint. The Recordings tab says what happened instead (R-57).
- **The Sound meter could crash on its second visit.** The microphone tap was installed before
  `AVAudioEngine.start()` but only removed if the engine had started, so a start that threw —
  another app holding the microphone — stranded it, and the next visit trapped inside AVFAudio
  installing a second tap on the same bus (R-34).
- **A phone call froze the sound reading at its last value.** There was no interruption, route
  change or media-reset handling anywhere in the app: the engine stopped and the 10 Hz timer
  kept republishing a number that had stopped being true, including into a running recording.
  The meter now says "Paused — something else is using the microphone" and comes back by
  itself; a headset change reinstalls the tap against the new format (P-2, R-34).
- **The microphone and camera kept running after the user left a tool.** Both tool views
  activated on appear *and* again when the permission card was answered, so the count never
  reached zero and the capture session — and its privacy indicator — stayed on for the rest of
  the app's life. Activation is now a lease the hub hands out and the view gives back, which
  makes an unbalanced claim impossible rather than merely unlikely (R-19, R-64).
- **Invalid coordinates crashed the app.** `Int(_: Double)` traps on NaN, and Core Location
  reports an unknown position as NaN, so choosing degrees-minutes-seconds without a fix was
  fatal. Non-finite values format as "—", as they already did elsewhere (R-8).
- **Control Centre ended a recording.** `.inactive` was treated like backgrounding, so a swipe
  into Control Centre, a half-swipe to the app switcher or an incoming-call banner all stopped
  the session for good. Only a real backgrounding does now (R-41).
- **Proximity monitoring was switched on and off dozens of times a second.** The grid resolved
  hardware availability inside its body for all 19 readings on every redraw, which toggled the
  proximity sensor — the one sensor the app goes out of its way to keep off, because it blanks
  the screen — and called Core Location's blocking availability check on the main thread.
  Hardware support is now resolved once, at startup (R-7, R-68).
- **Saved metadata could overstate what was in the file.** A sample was counted as recorded
  before its row was written, so a refused write left the session claiming more samples than
  the CSV held. Rows now count only once they land, dropped rows are reported with a number,
  and the most serious failure is the one shown — a discarded recording is no longer masked by
  a milder "may be short" note (R-43, R-45).
- **Recordings were never flushed to disk.** `FileHandle.synchronize()` is now called before a
  track's file is closed, so a panic or hard reset cannot lose the tail of a session.
- **A stale location fix could be recorded before the recording started.** Providers replay
  their last value so a view is not blank, and a fix can be minutes old; recording it wrote a
  row with a negative `elapsed_s`. Samples older than the session are dropped (R-45).
- **Live and recorded statistics disagreed.** On the sample where a reading gained a channel —
  the pedometer, once you start walking — the live buffer skipped the channels it already knew.
- **A long session could exhaust memory when opened.** Its CSV was read into one `String` and
  split; it is now streamed and thinned as it is read, so the cost follows the chart rather
  than the length of the recording (R-43).
- Charts rebuilt the whole sample ring once per axis per redraw; recording metadata was
  JSON-decoded on every list row of every redraw; a non-finite value could break a sparkline.

### Changed

- `SensorHub.activate(_:rate:)` returns a `SensorLease`, given back with `release(_:)`, in
  place of a matching `deactivate(_:rate:)` call maintained by hand across six views.
- Recordings are created with explicit file protection
  (`completeUntilFirstUserAuthentication`) rather than the default (R-57).
- `SWIFT_TREAT_WARNINGS_AS_ERRORS` and `GCC_TREAT_WARNINGS_AS_ERRORS` are on; the tree builds
  clean.

## [0.2.0] — 2026-10-18

Recording and CSV export: §8 of the spec in full. Built and run in the Simulator against the
synthetic source; the sample rates still need checking against real sensors on a phone.

### Added

- **Recording sessions** — a recording service that samples the chosen readings through
  `SensorHub` while Readout is in the foreground, writing each reading to its own CSV file as
  it goes. Samples are taken from the hub's own tap rather than the chart history, which
  decimates to 10 Hz (R-6, R-37, R-65).
- **Sample rates** — Low (1 Hz), Medium (10 Hz) and High (50 Hz). High drives the four Core
  Motion readings; the microphone, camera and device readings are capped at the chosen rate
  but not driven; location, air pressure and the pedometer are logged as their frameworks
  deliver them (R-39).
- **New Recording** — a checklist of every reading this iPhone has, with the sample rate and
  its consequences spelled out, from the Recordings tab or from a Record button. A reading
  that needs a permission asks for it here, and one that is refused is named rather than
  silently dropped (R-37, R-38).
- **Recording bar** — elapsed time, sample count and Stop, floating above the tab bar in
  whichever tab is open, with the screen kept awake for as long as the session runs (R-40).
- **Foreground only** — leaving Readout stops the session and saves it with an "interrupted"
  note, as Q-3 decided (R-41).
- **Sessions** — SwiftData holds the metadata and the samples stay in CSV files on disk, one
  folder per session under Application Support. The tab lists sessions newest first with
  their duration, reading count and size (R-42, R-57, R-61).
- **Session view** — a chart of the whole recording read back from its CSV, min/max/average
  per channel, and Rename, Delete and Export (R-43).
- **CSV export** — one file per reading, shared together through the share sheet, with an
  ISO 8601 timestamp carrying milliseconds and the phone's time-zone offset, elapsed seconds,
  and one column per value named after its unit, exactly as SPEC §8.4 sets out. Values are
  written in the unit they are stored in, so a file means the same thing whatever the
  exporting phone was set to show (R-44, R-45).
- **Record buttons** — on every reading detail view and on all four tools, each opening New
  Recording with that reading already ticked (R-29, R-36).
- **Recording haptics** — a tap as a session starts and another as it stops, behind the
  existing Settings switch (R-51).
- **Unit tests** — 39 more, over the CSV format against the spec's own example, column naming
  for all 19 readings, the sample-rate gate at each rate and cadence, session and file naming,
  track statistics, and reading a session's CSV back for its chart.

### Changed

- `ActivationRate` gained a 50 Hz case, asked for only by a High recording (R-39).
- The Simulator's synthetic source now follows the rate it is asked for, and delivers the
  location, altimeter and pedometer readings about once a second as their frameworks do, so a
  recording made in the Simulator has the shape one made on a phone would (R-71).

## [0.1.0] — 2026-10-18

First MVP: every reading and every instrument, live on device. Recording and CSV export are
not in this release.

### Added

- **Repository and project setup** — Xcode project (iOS 26 deployment target, Swift 6 language
  mode, no third-party dependencies), shared scheme, unit test target, `README.md`,
  `.gitignore`, `AGENTS.md`, `CLAUDE.md`, `docs/SPEC.md` and this changelog.
- **App shell** — three tabs (Readings, Tools, Recordings) in the system glass tab bar, with a
  Settings sheet from the Readings toolbar (R-1, R-23, R-46).
- **Reading catalog** — all 19 readings across Motion, Environment, Location and
  Device & activity, each with its SF Symbol, source, unit, permission, explainer, "Try this"
  idea and comparison scale (R-2, R-28).
- **Sensor layer** — a single `SensorHub` owning one Core Motion manager, one Core Location
  manager, the audio session and the capture session, with reference-counted start/stop per
  reading and a stop on backgrounding (R-63, R-64, R-65).
- **Providers** — Core Motion (accelerometer, gyroscope, device motion, magnetometer,
  altimeter, pedometer), Core Location (coordinates, altitude, speed, course, accuracy,
  heading), AVFoundation microphone level metering and camera-exposure light metering, and
  UIKit/ProcessInfo device readings (battery, proximity, thermal state) (R-3, R-9, R-66–R-70).
- **Readings grid** — two columns of glass cards under group headers, each with a live value
  and a sparkline, and all four tile states: live, tap to measure, tap to allow, hidden
  (R-15–R-21).
- **Reading detail view** — large live value with per-axis colours, Swift Charts live chart with
  10 s / 1 min / 5 min windows, pause, per-axis toggles, min/max/average with reset, comparison
  scale, explainer card, gravity toggle for acceleration, and long-press to copy the value
  (R-24–R-28, R-30, R-31).
- **Spirit level** — surface and edge modes switching automatically by orientation, angle to
  0.1°, zero calibration, hold to freeze, haptic tick at level (R-32).
- **Compass** — rotating dial, true/magnetic north toggle, bearing lock with drift, coordinates
  and altitude, system calibration prompt on poor accuracy, haptic ticks at the cardinal
  points (R-33).
- **Sound meter** — current, peak and average dB, fast/slow response, live history chart,
  comparison scale and a warning colour from 85 dB; levels only, audio is never recorded
  (R-34, R-56).
- **Light meter** — approximate lux from camera exposure, live preview, tap-to-meter a spot,
  front/rear switch and hold to freeze; no frame is ever saved (R-11, R-12, R-35, R-67).
- **Permissions** — asked only at the point of use, each behind a one-line explanation card,
  with "Tap to allow" tiles and a link to Settings after a denial (R-54, R-55).
- **Settings** — unit system override, haptics switch, sound and light calibration offsets,
  tile visibility, About and Privacy (R-8, R-22, R-23).
- **Mock sensor source** — synthetic data standing in for the hardware the Simulator lacks, so
  the UI is demoable and previewable without a device (R-71).
- **Unit tests** — 40 tests over unit conversion, dB and lux maths, the history buffer and its
  statistics, comparison scales, spirit-level geometry and the catalog's own invariants.

### Known limitations

- Recording and CSV export are not implemented; the Recordings tab explains that and the Record
  buttons are absent until v0.2.0 (R-6, R-29, R-36–R-45).
- Sound and light figures are uncalibrated estimates and are labelled as such. Per-model
  calibration tables are empty (R-10, R-66, R-72).
- Edit mode is reached from the Edit button only, and tiles cannot be dragged into a new
  order; they can be hidden and restored (R-22).
- Chart audio graphs for VoiceOver are not implemented (R-52).
- No reading has been verified on physical hardware yet: the app has only been built and run
  in the Simulator, where every value comes from the synthetic source and the permission gate
  is skipped.

[Unreleased]: https://github.com/leeyenkai/Readout/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/leeyenkai/Readout/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/leeyenkai/Readout/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/leeyenkai/Readout/releases/tag/v0.1.0
