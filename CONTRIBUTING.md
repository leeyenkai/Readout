# Contributing to Readout

Readout is a hobby project with a short specification and firm boundaries. The quickest way to
have a change accepted is to read [`AGENTS.md`](AGENTS.md) first — it is the working agreement
for this repository, and it applies to people as much as to agents.

## Before you write any code

- **[`docs/SPEC.md`](docs/SPEC.md) is the source of truth for scope.** §2.2 lists what v1
  deliberately leaves out, §12 the milestones and §13 the questions still open. Work outside
  the current milestone belongs in a proposal, not in a commit.
- Requirements carry stable IDs (`R-nn`). Cite them in commits, in the changelog and in
  comments, so a line of code can be traced back to the reason it exists.

## The rules that are not negotiable

- **No network.** No URLSession, no analytics, no crash reporting, no remote config. The one
  exception is the optional Apple Maps route view, which is off by default (R-81). A change
  that would make a request is a change to the premise of the app (R-59).
- **No third-party dependencies.** Adding one needs a decision recorded in the specification
  first.
- **Microphone audio and camera frames stay in memory**, are used only to derive a number, and
  are never written anywhere (R-56).
- **Sensors run only while something is looking at them.** Views take a lease from `SensorHub`
  and give it back; nothing reaches for Core Motion, Core Location or AVFoundation directly
  (R-63, R-64).
- **Nothing is presented as more certain than it is.** Sound and light are estimates and say so
  (P-2, R-72).

## Building and testing

```bash
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'generic/platform=iOS Simulator' build
xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'platform=iOS Simulator,name=Readout iPhone' test
```

Warnings are errors. New files under `Readout/` and `ReadoutTests/` are picked up automatically
— the target uses file-system-synchronized groups, so never hand-edit `project.pbxproj` to add
one.

Pure logic — unit conversion, dB and lux maths, statistics, formatting — lives in `Model/` so
the tests can cover it without hardware. If a change can be tested, it should be.

## What a change should carry with it

- An entry in [`CHANGELOG.md`](CHANGELOG.md) under `## [Unreleased]`, citing requirement IDs.
- An honest status in [`docs/SPEC.md`](docs/SPEC.md) for anything it finishes, or only partly
  finishes. Do not mark something Done that has not been verified to work.
- A commit message in the imperative mood that says *why*, not only what.

## Saying what you verified

The Simulator has no sensors: every reading there comes from a synthetic source. Say plainly
whether a change was checked on a physical iPhone, in the Simulator, or not at all. An honest
"not verified on hardware" is worth more than a confident claim that turns out to be guesswork.
