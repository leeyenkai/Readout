# Readout

A free, lightweight iPhone app that turns the phone's built-in sensors into clear, live
readings — and explains what each one actually measures.

Readout shows 19 readings across motion, environment, location and device activity, each with a
live chart, min/max/average, a plain-English explainer and a scale of everyday comparisons
("60 dB is a conversation; 85 dB is heavy traffic"). It adds four instruments: a spirit level,
a compass, a sound meter and a light meter.

It is a hobby project. No ads, no in-app purchases, no accounts, and no network requests at all.

## Status

**v0.3.0 — release readiness.** Every reading, every instrument, recording and CSV export, the
app icon, and the scaffolding an App Store submission needs. What is left before 1.0 is the
work a build machine cannot do: verifying the readings on a real iPhone, calibrating sound and
light against a reference meter, and a TestFlight pass — the checklist is
[`docs/RELEASE.md`](docs/RELEASE.md) §2.

**Nothing has been verified on physical hardware yet.** Everything here was built and run in
the Simulator, where the numbers come from a synthetic source.

See [`CHANGELOG.md`](CHANGELOG.md) for what has shipped and [`docs/SPEC.md`](docs/SPEC.md) §12
for the milestones.

## Requirements

- iOS 26.0 or later, iPhone only
- Xcode 27 (iOS 27 SDK), Swift 6.4 toolchain, Swift 6 language mode
- No third-party dependencies

## Build and run

```bash
git clone https://github.com/leeyenkai/Readout.git
cd Readout
open Readout.xcodeproj
```

Or from the command line:

```bash
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'generic/platform=iOS Simulator' build
```

Run the tests with:

```bash
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'platform=iOS Simulator,name=Readout iPhone' test
```

The Simulator has almost no sensors, so Readout falls back to a synthetic source there: the UI
is complete and demoable, but the numbers are made up. Real readings need a physical iPhone.

## What it reads

| Group | Readings |
| --- | --- |
| **Motion** | Acceleration, rotation rate, orientation, magnetic field, heading |
| **Environment** | Air pressure, relative altitude, sound level, light |
| **Location** | Coordinates, GPS altitude, speed, course, accuracy |
| **Device & activity** | Steps/distance/floors, cadence and pace, proximity, battery, thermal state |

Two things iOS does not expose, and Readout therefore does not pretend to have: **ambient light**
(measured here through the camera, so it is an estimate) and **air temperature** (not available at
all — "Phone heat" is the device's own thermal state, not the room's).

## Privacy

Everything is measured and stored on the phone. The app makes no network requests, contains no
analytics or crash-reporting SDKs, and its App Store privacy label is "Data Not Collected".
Microphone audio and camera frames are read in memory to derive a level and are never saved.

Permissions are requested only when a reading needs one: Motion & Fitness (pressure, altitude,
steps), Location While Using (location group, true north), Microphone (sound), Camera (light).

## Repository layout

| Path | Contents |
| --- | --- |
| [`docs/SPEC.md`](docs/SPEC.md) | Specification and requirement IDs — the source of truth for scope |
| [`AGENTS.md`](AGENTS.md) | Working agreement: architecture rules, conventions, constraints |
| [`CLAUDE.md`](CLAUDE.md) | Claude Code pointer to `AGENTS.md` |
| [`CHANGELOG.md`](CHANGELOG.md) | Release history |
| [`docs/RELEASE.md`](docs/RELEASE.md) | What is done for release, and the on-device checklist that still gates v1.0 |
| `Readout/` | App source: `App/`, `Model/`, `Sensors/`, `Features/`, `Support/` |
| `ReadoutTests/` | Unit tests for the pure logic (units, dB/lux maths, statistics) |

## Contributing

Read [`AGENTS.md`](AGENTS.md) before changing anything — it covers the architecture rules, the
privacy constraints and the requirement that `CHANGELOG.md` and `docs/SPEC.md` move with the
code.

## Licence

[MIT](LICENSE).
