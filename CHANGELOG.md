# Changelog

All notable changes to Readout are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). `R-nn` references point at
requirement IDs in [`docs/SPEC.md`](docs/SPEC.md).

## [Unreleased]

Nothing yet. Next milestone is **v0.3.0 — Calibration & accessibility** (`docs/SPEC.md` §12).

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

[Unreleased]: https://github.com/leeyenkai/Readout/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/leeyenkai/Readout/releases/tag/v0.1.0
