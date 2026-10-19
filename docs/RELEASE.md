# Releasing Readout

What stands between a green build and an App Store submission. Everything in §1 is done in
the repository; everything in §2 needs an Apple Developer account and a physical iPhone, and
nobody can do it from a build machine.

> **Archiving will fail until `DEVELOPMENT_TEAM` is set.** It is deliberately blank: there is
> no team to sign with yet. Set it in Xcode (target → Signing & Capabilities → Team) or add
> `DEVELOPMENT_TEAM = ABCDE12345;` beside `CODE_SIGN_STYLE` in `project.pbxproj`.

## 1. In the repository — done

| Item | Where |
| --- | --- |
| App icon, all four renditions | `Readout/AppIcon.icon` (Icon Composer document; open it in Icon Composer to edit) |
| Privacy manifest | `Readout/PrivacyInfo.xcprivacy` — no tracking, no collected data, `UserDefaults` (CA92.1) and disk-space (E174.1) declared |
| Export compliance | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` — the app makes no network requests at all |
| Permission strings | Four `INFOPLIST_KEY_NS*UsageDescription` entries, each saying what the sensor is for and that nothing leaves the phone |
| Launch screen | `INFOPLIST_KEY_UILaunchScreen_Generation = YES` |
| Licence | `LICENSE` (MIT) |
| CI | `.github/workflows/ci.yml` — builds and runs the test suite on every push |
| Warnings | `SWIFT_TREAT_WARNINGS_AS_ERRORS` and `GCC_TREAT_WARNINGS_AS_ERRORS` are on; the tree builds clean |

## 2. Before submitting

### Signing and identifiers

- [ ] Set `DEVELOPMENT_TEAM`.
- [ ] Register `com.leeyenkai.Readout` in App Store Connect. The bundle identifier in the
      project must match exactly.
- [ ] Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`, and move `[Unreleased]` in
      `CHANGELOG.md` to a version heading with a date (AGENTS.md §8).

### On-device verification — the real gate

The Simulator has almost no sensors, so everything Readout shows there comes from
`MockSensorSource` (R-71). None of the following has been confirmed on hardware, and v1.0 in
`docs/SPEC.md` §12 is not honest until it has:

- [ ] Every one of the 19 readings produces a sensible value on a real iPhone.
- [ ] The permission flow — each of the four prompts appears when it should, and a refusal
      leaves the rest of the app working.
- [ ] High (50 Hz) recording actually reaches 50 Hz from Core Motion (R-39).
- [ ] Audio interruption: start the Sound meter, take a phone call, hang up. The meter should
      say "Paused", then come back by itself — never hold a stale number.
- [ ] Route change: plug in and unplug headphones while the Sound meter runs.
- [ ] Haptics at level, at the compass points, and on recording start and stop (R-51).
- [ ] Sound and light against a reference meter; record the offsets in
      `DeviceCalibration` for that model identifier (R-10, R-66, R-72).
- [ ] Thermal state leaves `nominal` under load.
- [ ] A recording survives a swipe into Control Centre and stops on a real backgrounding.

### App Store Connect

- [ ] **Privacy label: "Data Not Collected".** Nothing is gathered, nothing is sent (R-59).
- [ ] Category: Utilities. Secondary: Education is a fair fit for the explainers.
- [ ] Support URL — required. The GitHub repository's issues page will do.
- [ ] Marketing URL, if any. Optional.
- [ ] Description, keywords, promotional text.
- [ ] **Screenshots.** `scripts/screenshots.sh` captures the Home Screen icon and the readings
      grid from the Simulator, which is enough to lay out the listing — but those numbers are
      synthetic. Retake on hardware before submitting.
- [ ] Age rating: 4+.
- [ ] Export compliance is answered by the Info.plist key; no further declaration is needed.

### Review notes worth writing

Reviewers sometimes ask why a utility wants the camera and microphone. Say it plainly:

> Readout is a sensor viewer. The camera is used only to read exposure metadata and estimate
> illuminance in lux — no frame is captured, displayed as media, or saved. The microphone is
> used only for level metering to estimate a decibel figure — no audio is recorded or saved.
> The app makes no network requests.

### TestFlight

- [ ] Internal build, installed on at least one real device, every screen opened.
- [ ] Run through §2's on-device list on that build, not on a debug build.
- [ ] Only then move `v1.0` in `docs/SPEC.md` §12 from Planned to Shipped.
