# Sharing Readout

Readout is a hobby project. There is no plan to put it on the App Store, so "ready" here means
ready to hand to somebody: they can clone it, build it, run it on their own iPhone, and either
trust what it tells them or know exactly where it is guessing.

Everything in §1 is done in the repository. §2 is what the person you share it with has to do,
§3 is the on-device work that decides whether the numbers can be trusted, and §4 is the
paperwork a submission would need, kept only in case that ever changes.

> **Signing is deliberately unset.** `DEVELOPMENT_TEAM` is blank, so whoever opens the project
> signs with their own team. Xcode asks for it the first time they build to a device; §2 says
> what to answer.

## 1. In the repository — done

| Item | Where |
| --- | --- |
| App icon, all four renditions | `Readout/AppIcon.icon` (Icon Composer document; open it in Icon Composer to edit) |
| Privacy manifest | `Readout/PrivacyInfo.xcprivacy` — no tracking, no collected data, `UserDefaults` (CA92.1) and disk-space (E174.1) declared |
| Permission strings | Four `INFOPLIST_KEY_NS*UsageDescription` entries, each saying what the sensor is for and that nothing leaves the phone |
| Launch screen | Black, from the `LaunchBackground` colour, declared in `Config/Info.plist` with generation off — so the launch matches the default true-black look in Light mode too |
| Orientation | Portrait only (`INFOPLIST_KEY_UISupportedInterfaceOrientations`), matching R-1 |
| Background modes | `Config/Info.plist` — `location` and nothing else. Xcode's generator has no build setting for `UIBackgroundModes`, so that one key lives in a partial plist the generated keys are merged on top of. The microphone and camera deliberately have no mode (R-83) |
| Screenshots | `docs/screenshots/` — Simulator captures, used in the README. The numbers in them are synthetic |
| Licence | `LICENSE` (MIT) — anyone may take this and do what they like with it |
| Contributing | `CONTRIBUTING.md`, and `AGENTS.md` for the full working agreement |
| CI | `.github/workflows/ci.yml` — builds and runs the test suite on every push |
| Warnings | `SWIFT_TREAT_WARNINGS_AS_ERRORS` and `GCC_TREAT_WARNINGS_AS_ERRORS` are on; the tree builds clean |
| Export compliance | `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption = NO` — the app uses no encryption. It makes no network request of its own; the optional Apple Maps route view has iOS fetch map tiles over the system's own transport (R-81) |

## 2. Running it on an iPhone

What somebody needs, start to finish:

1. **Xcode 26 or later** and an iPhone on **iOS 26 or later**. The Simulator needs neither a
   team nor a device, and is enough to see every screen — but every number there is synthetic
   (R-71).
2. **Their own signing team.** Open `Readout.xcodeproj` → target *Readout* → Signing &
   Capabilities → Team. A free Apple ID works; builds signed with one stop running after seven
   days and have to be rebuilt.
3. **A bundle identifier they can use.** `com.leeyenkai.Readout` is the one in the project. A
   free account will take any unique identifier, so changing the prefix to their own is the
   simplest fix if Xcode complains that this one is unavailable.
4. **Trust the developer certificate on the phone** the first time: Settings → General → VPN &
   Device Management.
5. **Permissions as they go.** Nothing is asked for at launch. Motion & Fitness, Location,
   Microphone and Camera are each requested the first time a reading needs one, behind a card
   saying why (R-54).

Worth saying out loud when you hand it over: **sound and light are estimates**, worked out from
the microphone's signal level and the camera's exposure, because iOS exposes neither an ambient
light sensor nor a thermometer. Both carry a "≈", and **Calibrate** in either tool will correct
them against a real meter (R-75). "Phone heat" is the device's own thermal state, not the
room's.

## 3. On-device verification — what makes the numbers trustworthy

The Simulator has no sensors: everything Readout shows there comes from `MockSensorSource`
(R-71). None of the following has been confirmed on hardware, and v1.0 in `docs/SPEC.md` §12 is
not honest until it has:

- [ ] Every one of the 19 readings produces a sensible value on a real iPhone.
- [ ] **The Attitude tool (R-86, R-87).** Hold the phone upright and tap Recentre: the model
      faces you. Tip it forward, roll it, turn on the spot: the model does the same, the right
      way round, in every pose including upright. Push the phone sideways: the model sways the
      way it moved and settles. Watch for sway caused by turning alone, and check frame rate and
      warmth over a few minutes on a ProMotion phone.
- [ ] **The spirit level's bubble rises to the high side** on both axes, flat and on each of the
      four edges, and a long edge reads near 0°, not 90° (R-32).
- [ ] With Location refused: Acceleration, Orientation and the level still run, and the compass
      reads magnetic north and says so (R-63, R-33).
- [ ] A first-ever recording that includes Coordinates: answer the location prompt, lock the
      phone, and the recording carries on — Coordinates was not dropped (R-38, R-82).
- [ ] With the Sound meter open, start a location-only recording and lock the phone: no orange
      microphone indicator while Readout is in the background (R-83).
- [ ] Open the Sound meter, then switch to another tab: the orange indicator goes out and stays
      out. The same for the Light meter and the green indicator (R-64).
- [ ] The sound level starts at the room's level when the meter opens, not 20 dB low (R-66).
- [ ] Move between tabs during a location recording: the CSV has no duplicated rows (R-45).
- [ ] The permission flow — each of the four prompts appears when it should, and a refusal
      leaves the rest of the app working.
- [ ] High (50 Hz) recording actually reaches 50 Hz from Core Motion (R-39).
- [ ] Audio interruption: start the Sound meter, take a phone call, hang up. The meter should
      say "Paused", then come back by itself — never hold a stale number.
- [ ] Route change: plug in and unplug headphones while the Sound meter runs.
- [ ] Haptics at level, at the compass points, and on recording start and stop (R-51).
- [ ] Sound and light against a reference meter. Use **Calibrate** in the Sound meter and the
      Light meter (R-75) to find the correction, then copy it into `DeviceCalibration` for the
      model identifier Settings names, so every phone of that model starts from it
      (R-10, R-66, R-72).
- [ ] Thermal state leaves `nominal` under load.
- [ ] A recording survives a swipe into Control Centre.
- [ ] **Background recording (R-82, R-85), the biggest untested thing in the release.** Start a
      session that includes Coordinates, lock the phone, and leave it for ten minutes. The blue
      location indicator should be showing the whole time. Then come back and open the CSVs:
      the rows should be continuous at the chosen rate, with no gap where the screen was off.
      The Simulator shows gaps here because it has no fixes arriving to keep the process
      scheduled, so this check is the only thing that can settle it.
- [ ] A session with **no** location reading still stops and saves on backgrounding, and the
      New Recording sheet said so beforehand (R-82).
- [ ] A session including Sound level or Light stops on backgrounding whatever else it
      records, and neither the orange nor the green indicator ever appears with the app in the
      background (R-83).
- [ ] Battery cost of a long background session — a journey's worth, not a few minutes.
- [ ] Export a recording through the share sheet and open the CSV somewhere else (R-44, R-45).

When this list is done on a real phone, move `v1.0` in `docs/SPEC.md` §12 from Planned to
Shipped — and not before.

## 4. If it ever did go to the App Store

Not planned, and nothing in the repository depends on it. Kept here so the decision does not
have to be researched twice:

- Signing: set `DEVELOPMENT_TEAM`, and register the bundle identifier in App Store Connect so
  the two match exactly.
- Privacy label: **"Data Not Collected"**. Nothing is gathered, nothing is sent (R-59).
- Category: Utilities; Education is a fair secondary for the explainers. Age rating 4+.
- A support URL is required; the repository's issues page would do.
- Screenshots would have to be retaken on hardware — the ones in `docs/screenshots/` are
  Simulator captures of synthetic data.
- Export compliance is already answered by the Info.plist key.
- Reviewers tend to ask why a utility wants the camera and microphone. The plain answer:

  > Readout is a sensor viewer. The camera is used only to read exposure metadata and estimate
  > illuminance in lux — no frame is captured, displayed as media, or saved. The microphone is
  > used only for level metering to estimate a decibel figure — no audio is recorded or saved.
  > The app makes no network requests of its own. Showing a recorded route on Apple Maps, which
  > is off by default and chosen by the user, has iOS fetch map tiles; nothing measured or
  > recorded is ever uploaded.
