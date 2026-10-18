# Readout — Specification

**Status:** Draft 2 (living document), reconciled against v0.1.0 · **Target:** v1.0 · **Last updated:** 2026-10-18

Source of truth for what Readout is and is not. Derived from *Readout — App Spec (Draft 1)*
(Claude Doc, 2026-10-18). This file supersedes that doc; changes land here first.

Requirements carry stable IDs (`R-nn`) so code, commits and the changelog can cite them.
Requirement status is one of **Done**, **Partial**, **Planned** or **Deferred**, and reflects
the milestone table in [§11](#11-milestones).

---

## 1. Overview

Readout is a free, lightweight iPhone app that turns the phone's built-in sensors into clear,
live readings for curious everyday users. It explains what each sensor measures, compares
readings to everyday references, and adds four simple instruments: spirit level, compass,
sound meter and light meter.

It is a hobby project with no monetisation: no ads, no in-app purchases, no account.

### 1.1 Design principles

| ID | Principle |
| --- | --- |
| P-1 | **Glanceable first.** Any reading should make sense within a couple of seconds. |
| P-2 | **Honest about sources.** Every number says where it comes from and how precise it is; nothing is presented as a sensor that isn't one. |
| P-3 | **Light and quiet.** Sensors run only while they are on screen or recording; the app needs no network. |
| P-4 | **Native feel.** Built in Apple's current design language (Liquid Glass, SF fonts and symbols, standard system behaviours). |

---

## 2. Scope for v1

Version 1 is an iPhone-only app covering four sensor groups, four instrument tools and
foreground recording with CSV export.

### 2.1 In scope

| ID | Requirement | Status |
| --- | --- | --- |
| R-1 | iPhone, portrait-first | Done |
| R-2 | Live readings for Motion, Environment, Location, and Device & activity | Done |
| R-3 | Light from a camera-based light meter; device thermal state as the only heat-related reading | Done |
| R-4 | A detail view per reading: live chart, min/max/average, explainer and everyday comparisons | Done |
| R-5 | Instrument tools: spirit level, compass, sound meter, light meter | Done |
| R-6 | Foreground recording of chosen sensors, exported as CSV through the share sheet | Done (v0.2.0) |

### 2.2 Out of scope for v1

| ID | Exclusion |
| --- | --- |
| X-1 | iPad, Mac and Apple Watch versions |
| X-2 | Air temperature, humidity or any weather data |
| X-3 | External Bluetooth sensors |
| X-4 | Recording while the app is in the background |
| X-5 | Home Screen widgets, Live Activities and Control Centre controls |
| X-6 | Accounts, cloud sync, analytics, ads and in-app purchases |

---

## 3. Sensors and readings

Readout shows 19 readings across four groups, all from public iOS frameworks. Units follow
the phone's region (metric or imperial), with an override in Settings.

| # | Group | Reading | Source | Units | Permission |
| --- | --- | --- | --- | --- | --- |
| 1 | Motion | Acceleration (x, y, z) | Core Motion, accelerometer | g, m/s² | None |
| 2 | Motion | Rotation rate (x, y, z) | Core Motion, gyroscope | °/s | None |
| 3 | Motion | Orientation (pitch, roll, yaw) | Core Motion, device motion | degrees | None |
| 4 | Motion | Magnetic field (x, y, z) | Core Motion, magnetometer | µT | None |
| 5 | Motion | Heading | Core Location, heading | degrees, true or magnetic | Location, for true north only |
| 6 | Environment | Air pressure | Core Motion, altimeter (barometer) | hPa, inHg | Motion & Fitness |
| 7 | Environment | Relative altitude | Core Motion, altimeter | m, ft (change since start) | Motion & Fitness |
| 8 | Environment | Sound level | AVFoundation, microphone level metering | dB (estimate) | Microphone |
| 9 | Environment | Light | AVFoundation, camera exposure data | lux (estimate) | Camera |
| 10 | Location | Coordinates | Core Location | decimal degrees or DMS | Location (While Using) |
| 11 | Location | GPS altitude | Core Location | m, ft | Location (While Using) |
| 12 | Location | Speed | Core Location | km/h, mph, m/s | Location (While Using) |
| 13 | Location | Course | Core Location | degrees | Location (While Using) |
| 14 | Location | Accuracy | Core Location | m (horizontal, vertical) | Location (While Using) |
| 15 | Device & activity | Steps, distance, floors | Core Motion, pedometer | steps, km/mi, floors | Motion & Fitness |
| 16 | Device & activity | Cadence and pace | Core Motion, pedometer | steps/min, min/km | Motion & Fitness |
| 17 | Device & activity | Proximity | UIKit, proximity sensor | near / far | None |
| 18 | Device & activity | Battery | UIKit, battery monitoring | %, charging state | None |
| 19 | Device & activity | Thermal state | ProcessInfo | nominal, fair, serious, critical | None |

| ID | Requirement | Status |
| --- | --- | --- |
| R-7 | Every reading checks hardware availability at runtime; a reading the device lacks is hidden rather than shown as broken. | Done |
| R-8 | Units follow the phone's region, with a metric/imperial override in Settings. | Done |

---

## 4. Light and temperature

iOS gives apps no access to the ambient light sensor or to any temperature sensor, so v1
measures light through the camera and shows no air temperature at all.

### 4.1 Light: camera light meter

| ID | Requirement | Status |
| --- | --- | --- |
| R-9 | Read the camera's ISO, shutter time and aperture, compute an exposure value, and convert it to an approximate lux figure. | Done |
| R-10 | Calibrate the conversion per iPhone model where needed; show the value with "≈" and a "camera estimate" note. | Partial — global offset in Settings; per-model table not yet populated |
| R-11 | The camera runs only while the Light detail view or the Light Meter tool is open; the home tile shows the last reading and "Tap to measure". | Done |
| R-12 | No image is saved or shown on the home grid; only the derived number is kept. | Done |

### 4.2 Temperature: device thermal state only

| ID | Requirement | Status |
| --- | --- | --- |
| R-13 | The Thermal State reading shows the phone's own heat level (nominal, fair, serious, critical), labelled "Phone heat", not "temperature". | Done |
| R-14 | Its explainer says plainly that iPhones don't let apps read air temperature, and that this reading is about the phone, not the room. | Done |

Weather data and Bluetooth thermometers were considered and left out of v1; see
[§12 Open questions](#12-open-questions).

---

## 5. Home screen and navigation

Readout has three tabs (Readings, Tools, Recordings); Readings opens on a grid of live tiles,
each one tap from its detail view. Record buttons in detail views and tools jump to New
recording with that reading already selected.

### 5.1 Tile grid

| ID | Requirement | Status |
| --- | --- | --- |
| R-15 | Two columns of glass cards under four group headers: Motion, Environment, Location, Device & activity. | Done |
| R-16 | Each tile shows an SF Symbol, the reading's name, one live value with its unit, and a small sparkline of the last few seconds. | Done |
| R-17 | Three-axis readings show their most useful single value on the tile (for example, total acceleration or heading); the axes appear in the detail view. | Done |

### 5.2 Tile states

| ID | State | Applies to | Status |
| --- | --- | --- | --- |
| R-18 | **Live** — updating while visible | most readings | Done |
| R-19 | **Tap to measure** — the camera, microphone and proximity sensor never run just because the grid is open | light, sound, proximity | Done |
| R-20 | **Tap to allow** — the reading needs a permission not yet granted | permission-gated readings | Done |
| R-21 | **Hidden** — the device lacks the sensor | per device | Done |

### 5.3 Editing and settings

| ID | Requirement | Status |
| --- | --- | --- |
| R-22 | Edit mode (long-press or the Edit button) reorders, hides and restores tiles; the layout is saved on the device. | Partial — the Edit button hides, restores and persists; long-press entry and drag-reorder planned |
| R-23 | Settings opens as a sheet from the Readings toolbar: units, haptics, sound calibration offset, About and Privacy. | Done |

---

## 6. Sensor detail view

Tapping a tile opens one screen per reading: a large live value, a scrolling chart, quick
stats, and a short explainer with everyday comparisons.

### 6.1 Layout, top to bottom

| ID | Requirement | Status |
| --- | --- | --- |
| R-24 | Live value in large type; three-axis readings show x, y and z side by side, each in its axis colour. | Done |
| R-25 | Live line chart (Swift Charts) with a 10 s window by default, switchable to 1 min and 5 min; pause and resume; tap an axis to hide it. | Done |
| R-26 | Stats since the view opened: minimum, maximum, average, with a Reset button. | Done |
| R-27 | Comparison scale: the current value placed on a bar of everyday references. | Done |
| R-28 | Explainer card: what the sensor is, what it measures, how precise it is, and one "Try this" idea. | Done |
| R-29 | Record button that starts a recording with this reading pre-selected. | Done |
| R-30 | Acceleration shows motion with gravity removed by default, with a toggle to include gravity. | Done |
| R-31 | Long-pressing the live value copies it with its unit. | Done |

### 6.2 Everyday comparisons (draft values, all approximate)

| Reading | References |
| --- | --- |
| Sound level | 30 dB whisper · 40 dB quiet library · 60 dB conversation · 85 dB heavy traffic, where long exposure risks hearing · 100 dB concert |
| Light | under 1 lux moonlight · 50 lux dim living room · 300–500 lux office · 1,000 lux overcast day · 100,000 lux direct sun |
| Air pressure | 1013 hPa average at sea level · about 990 hPa stormy low · about 900 hPa at 1,000 m · about 750–800 hPa in an airliner cabin |
| Acceleration | 1 g phone at rest (gravity) · about 0.3 g car pulling away · about 0.8 g hard braking · 3–4 g roller coaster |
| Speed | 5 km/h walking · 10 km/h jogging · 20 km/h cycling · 80 km/h metro train |

---

## 7. Instrument tools

The Tools tab holds four full-screen instruments, each built for one job and usable at a glance.

| ID | Tool | What it shows | Source | Key interactions | Status |
| --- | --- | --- | --- | --- | --- |
| R-32 | Spirit level | Surface mode (phone flat): bubble in a circle, tilt in two axes. Edge mode (phone on its side): bar level with angle to 0.1° | Device motion (gravity vector) | Switches mode automatically by orientation; haptic tick at 0°; Zero button to calibrate on a known-flat surface; Hold to freeze the reading | Done |
| R-33 | Compass | Rotating dial with heading, cardinal letters, coordinates and altitude below | Core Location heading and location | True or magnetic north toggle; lock a bearing to show drift from it; haptic tick at N, E, S, W; calibration prompt when accuracy is poor | Done |
| R-34 | Sound meter | Current dB, peak and average, live history chart, comparison scale | Microphone level metering | Fast or slow response; Reset; warning colour at 85 dB and above; audio is never recorded, only levels | Done |
| R-35 | Light meter | Approximate lux, live camera preview with a metering spot, comparison scale | Camera exposure data | Tap the preview to meter a spot; switch front or rear camera; Hold to freeze the reading | Done |
| R-36 | Each tool has the same Record button as the detail view, so a level or sound session can be logged without leaving the tool. | | | | Done |

---

## 8. Recording and export

Recording logs the readings a user picks while the app is open, saves each session on the
device, and exports it as CSV through the share sheet. **All of §8 shipped in v0.2.0**, built
and run in the Simulator against the synthetic source; the rates still need checking against
real sensors (R-71).

### 8.1 Starting a recording

| ID | Requirement | Status |
| --- | --- | --- |
| R-37 | From the Recordings tab (New Recording) or the Record button on any detail view or tool. | Done |
| R-38 | Pick readings from a checklist; readings that need a permission ask for it here. | Done — a reading whose permission is refused is named and left out, the rest still record |
| R-39 | Pick a sample rate: Low (1 Hz), Medium (10 Hz) or High (50 Hz). High applies to motion readings; location, pressure and the pedometer record at their own native rate. | Done — sound, light and the device readings are capped at the chosen rate but cannot be driven faster; 50 Hz from Core Motion needs a phone to confirm |
| R-40 | While recording, the screen stays awake and a compact recording bar shows elapsed time, sample count and Stop. | Done — the bar is verified; the idle timer cannot be observed in the Simulator |

### 8.2 Leaving the app

| ID | Requirement | Status |
| --- | --- | --- |
| R-41 | Recording is foreground-only in v1. If the user leaves the app, the session stops and is saved with an "interrupted" note. | Done |

### 8.3 Sessions

| ID | Requirement | Status |
| --- | --- | --- |
| R-42 | The Recordings tab lists sessions newest first: auto-generated name (date, time, readings), duration and size. | Done |
| R-43 | A session view shows a chart and min/max/average per reading, with Rename, Delete and Export. | Done — the chart is read back from the session's own CSV |

### 8.4 CSV format

| ID | Requirement | Status |
| --- | --- | --- |
| R-44 | One CSV file per reading, all shared together through the share sheet (Files, AirDrop, Mail, and so on). | Done |
| R-45 | Columns: ISO 8601 timestamp with milliseconds and time-zone offset, elapsed seconds, then one column per value with its unit in the header. | Done — values are written in the unit they are stored in, so a file reads the same whatever the phone shows; a discrete reading adds a `state` column |

```csv
timestamp,elapsed_s,accel_x_g,accel_y_g,accel_z_g
2026-10-18T14:30:00.000+08:00,0.000,0.012,-0.981,0.034
2026-10-18T14:30:00.100+08:00,0.100,0.015,-0.979,0.031
2026-10-18T14:30:00.200+08:00,0.200,0.011,-0.983,0.036
```

---

## 9. Design language

Readout follows Apple's Liquid Glass design: content first, glass controls floating above it,
and system components wherever they exist.

| ID | Area | Requirement | Status |
| --- | --- | --- | --- |
| R-46 | Surfaces | Glass tab bar and toolbars; home tiles as glass cards over a plain system background; no custom chrome. | Done |
| R-47 | Type | SF Pro throughout; large readouts use monospaced digits so live numbers don't jitter as they change; numeric content transitions animate value changes. | Done |
| R-48 | Icons | One SF Symbol per reading, with symbol effects where they add meaning (for example, the sound tile's symbol reacting to level). | Done |
| R-49 | Colour | System colours with a single accent; fixed axis colours across the app (x red, y green, z blue); full dark mode and Increase Contrast support. | Done |
| R-50 | Motion | Gentle, physical animation (bubble, compass dial); all of it reduced or removed under Reduce Motion. | Done |
| R-51 | Haptics | Level reaching 0°, compass cardinal points, recording start and stop; one switch in Settings turns them off. | Done — recording haptics added in v0.2.0; not feelable in the Simulator |
| R-52 | Accessibility | Dynamic Type on every screen; VoiceOver reads each value with its unit on request rather than announcing every change; charts expose audio graphs; tools work one-handed. | Partial — Dynamic Type, VoiceOver labels and Reduce Motion done; chart audio graphs planned |
| R-53 | Language | English at launch; units and number formats follow the phone's region. | Done |

---

## 10. Permissions and privacy

Readout collects no data: everything is measured and stored on the phone, the app makes no
network requests, and the App Store privacy label is "Data Not Collected".

| Permission | Needed for | Asked when |
| --- | --- | --- |
| Motion & Fitness | Air pressure, relative altitude, steps, cadence | User first opens one of these readings or adds it to a recording |
| Location (While Using) | Location group; true north on the compass | User first opens a location reading or the compass |
| Microphone | Sound level, sound meter | User first opens the sound reading or tool |
| Camera | Light reading, light meter | User first opens the light reading or tool |

| ID | Requirement | Status |
| --- | --- | --- |
| R-54 | Permissions are asked only when needed, each preceded by a one-line card explaining why. | Done |
| R-55 | Tiles that lack permission show "Tap to allow"; after a denial they link to the app's page in Settings. | Done |
| R-56 | Microphone audio and camera frames are processed in memory and never saved; only the derived numbers are kept. | Done |
| R-57 | Recordings stay on the device until the user exports them; deleting the app deletes them. | Done — sessions live in Application Support, and deleting one removes its CSV files with it |
| R-58 | iOS shows its orange (microphone) and green (camera) indicators while those sensors are in use; the app never hides or works around them. | Done |
| R-59 | The app makes no network requests; no analytics, no crash reporting SDKs, no remote config. | Done |

---

## 11. Technical notes

The build is native Swift and SwiftUI targeting iOS 26 and later, with no third-party
dependencies.

### 11.1 Stack

| ID | Requirement | Status |
| --- | --- | --- |
| R-60 | SwiftUI with the Observation framework; Swift Charts for all charts. | Done |
| R-61 | Core Motion, Core Location and AVFoundation for sensors; SwiftData for session metadata, with samples written to CSV files on disk. | Done |
| R-62 | iOS 26 minimum, so Liquid Glass comes from the system rather than being imitated; this covers every iPhone that runs iOS 26. | Done |

Built with Xcode 27 / Swift 6.4 against the iOS 27 SDK; deployment target iOS 26.0.

### 11.2 Sensor lifecycle

| ID | Requirement | Status |
| --- | --- | --- |
| R-63 | One shared sensor service owns a single Core Motion manager, as Apple recommends, and hands readings to views. | Done |
| R-64 | A sensor starts when a view showing it appears and stops when it disappears or the app goes to the background. | Done |
| R-65 | Home tiles refresh at about 10 Hz; the level, compass and charts at display rate; recordings sample at the chosen rate, independent of the screen. | Done — recordings take their samples from the hub's tap, so a chart running at display rate neither slows nor speeds a session |

### 11.3 Per-sensor notes

| ID | Sensor | Note | Status |
| --- | --- | --- | --- |
| R-66 | Sound | Audio session in measurement mode to avoid automatic gain; RMS level converted to dBFS, then to an estimated dB with a per-model calibration offset. | Partial — user offset in Settings; per-model table not yet populated |
| R-67 | Light | Low-resolution capture session read only for exposure metadata; front and rear cameras need separate calibration. | Done |
| R-68 | Proximity | Turning on proximity monitoring blanks the screen when something covers the sensor, so it runs only inside its detail view, behind a "Start test" button. | Done |
| R-69 | Heading | Shows the system calibration prompt when heading accuracy is poor. | Done |
| R-70 | Pedometer | Shows today's totals from the system, plus live cadence and pace while walking. | Done |

### 11.4 Testing

| ID | Requirement | Status |
| --- | --- | --- |
| R-71 | Most sensors don't work in the Simulator, so the sensor service sits behind a protocol with a mock that replays synthetic data for previews and UI tests. | Done — the Simulator also skips the permission gate, since there is no real sensor to protect and no way to answer a Motion & Fitness prompt |
| R-72 | Calibration offsets for sound and light need checking on real devices against a reference meter. | Open — needs hardware |

---

## 12. Milestones

| Milestone | Contents | State |
| --- | --- | --- |
| **v0.1.0 — Readings & tools** | App shell and three tabs; all 19 readings with live providers; tile grid with all four states; detail views with charts, stats, comparisons and explainers; all four instrument tools; Settings; permission flow; mock source for Simulator and previews; 40 unit tests | Shipped — built and run in the Simulator; **not yet verified on physical hardware** |
| **v0.2.0 — Recording & export** | §8 in full: recording sessions, sample rates, recording bar, session list and detail, SwiftData metadata, CSV writing and share-sheet export, Record buttons wired up (R-6, R-29, R-36–45, R-51, R-57, R-61) | Shipped — recorded, listed, charted and exported in the Simulator against the synthetic source; **not yet verified on physical hardware** |
| **v0.3.0 — Calibration & accessibility** | Per-model sound and light calibration tables (R-10, R-66), chart audio graphs (R-52), drag-to-reorder tiles (R-22) | Next |
| **v1.0 — App Store** | App icon, screenshots, App Store privacy label ("Data Not Collected"), on-device testing of every reading, TestFlight pass | Planned |

---

## 13. Open questions

Decisions for the next round of refinement. The **Draft 1 answer** column records the
provisional choice v0.1.0 ships with; none of them is settled.

| # | Question | Draft 1 answer |
| --- | --- | --- |
| Q-1 | Home grid default: show all 19 readings, or a starter set of about 8 with the rest under Edit? | All 19, grouped |
| Q-2 | Compass and level tiles: open the detail view or jump straight to the tool? | Detail view; tools live in their own tab |
| Q-3 | Leaving the app mid-recording: stop and save, or pause and resume on return? | Stop and save with an "interrupted" note |
| Q-4 | Maximum recording length and a storage cap per session? | Undecided — v0.2.0 ships no cap; a three-axis reading at 50 Hz writes about 200 kB a minute |
| Q-5 | Sound meter calibration: fixed per-model offsets, user calibration against a reference meter, or both? | User offset ships in v0.1.0; per-model table in v0.3.0 |
| Q-6 | Recordings: device-only, or iCloud sync later? | Device-only |
| Q-7 | Temperature in a later version: nearby weather (labelled), Bluetooth thermometers, or neither? | Neither in v1 |
| Q-8 | Widgets, Control Centre controls or Shortcuts actions ("What's the air pressure?") in v1.1? | Undecided |
| Q-9 | iPad or Apple Watch later, given their different sensor sets? | Undecided |
| Q-10 | Name check: is "Readout" available on the App Store, and what does the icon look like? | Open |
| Q-11 | Re-check the latest iOS SDK before building, in case Apple has opened up light or temperature data. | Checked 2026-10-18 against the iOS 27 SDK: still no ambient-light or temperature API |
