## What this changes

<!-- One or two sentences. Cite the requirement IDs it touches, for example (R-34, R-66). -->

## Why

<!-- What was wrong, or what was missing. The commit message should say the same thing. -->

## Checks

- [ ] `xcodebuild -project Readout.xcodeproj -scheme Readout -destination 'generic/platform=iOS Simulator' build` is clean — warnings are errors here.
- [ ] The tests pass.
- [ ] `CHANGELOG.md` has an entry under `## [Unreleased]`.
- [ ] `docs/SPEC.md` says the truth about anything whose status this changes.
- [ ] No network call, no analytics, no new `Info.plist` usage key without a line in `docs/SPEC.md` §10.

## Verified how

<!-- Simulator, physical iPhone, or neither. Be plain about it: most of Readout's
     numbers cannot be confirmed without hardware. -->
