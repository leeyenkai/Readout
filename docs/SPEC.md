# Readout — Specification

**Status:** Draft 5 (living document), reconciled against v0.5.0 · **Target:** v1.0 · **Last updated:** 2026-10-20

Source of truth for what Readout is and is not. Derived from *Readout — App Spec (Draft 1)*
(Claude Doc, 2026-10-18). This file supersedes that doc; changes land here first.

Requirements carry stable IDs (`R-nn`) so code, commits and the changelog can cite them.
Requirement status is one of **Done**, **Partial**, **Planned** or **Deferred**, and reflects
the milestone table in [§12](#12-milestones).

---

## 1. Overview

Readout is a free, lightweight iPhone app that turns the phone's built-in sensors into clear,
live readings for curious everyday users. It is shared as source and built from Xcode; there is
no plan to publish it on the App Store. It explains what each sensor measures, compares
readings to everyday references, and adds four simple instruments: spirit level, compass,
sound meter and light meter.

It is a hobby project with no monetisation and no distribution: no ads, no in-app purchases,
no account, and nothing to sign up to.

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
| R-1 | iPhone, portrait-first | Done — portrait only from v0.4.0: every screen is laid out for it, and rotating the interface out from under a levelling measurement helps nobody |
| R-2 | Live readings for Motion, Environment, Location, and Device & activity | Done |
| R-3 | Light from a camera-based light meter; device thermal state as the only heat-related reading | Done |
| R-4 | A detail view per reading: live chart, min/max/average, explainer and everyday comparisons | Done |
| R-5 | Instrument tools: spirit level, compass, sound meter, light meter | Done |
| R-6 | Foreground recording of chosen sensors, exported as CSV through the share sheet | Done (v0.2.0) |
| R-76 | A recorded session's route, drawn from its own fixes without a map server, with Apple Maps behind an opt-in | Done (v0.5.0) |
| R-79 | A running session can be watched: every reading it is logging, live, with the route building up | Done (v0.5.0) |
| R-77 | Themes: the colour behind the readings and the accent on top, chosen by the user | Done (v0.5.0) |
| R-78 | An interface size, on top of the phone's own text size | Done (v0.5.0) |
| R-80 | The session limit is the user's to raise, for a journey longer than two hours | Done (v0.5.0) |
| R-82 | A recording that includes the user's position carries on when Readout is no longer in front | Partial — the session is no longer ended by backgrounding, and that is verified; whether it keeps *sampling* throughout needs a device (§11.4) |

### 2.2 Out of scope for v1

| ID | Exclusion |
| --- | --- |
| X-1 | iPad, Mac and Apple Watch versions |
| X-2 | Air temperature, humidity or any weather data |
| X-3 | External Bluetooth sensors |
| X-4 | **Narrowed in v0.5.0.** Recording in the background is no longer excluded outright: a session that records the user's position carries on, because Core Location's background updates are what keep the app alive (R-82). What remains excluded is background recording *without* a location reading — there is no mechanism for it — and the microphone and the camera in the background, which is a rule rather than a limitation (§8.5) |
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
| R-10 | Calibrate the conversion per iPhone model where needed; show the value with "≈" and a "camera estimate" note. | Partial — the mechanism ships in `DeviceCalibration`, keyed by hardware identifier, under the user's own correction, and v0.4.0 adds the guided flow that works that correction out (R-75). The per-model table is **deliberately empty**: an entry needs that model and a reference meter, and inventing one would make the reading look calibrated when it is not. Settings names the model identifier and says plainly that it has no measured baseline (R-72) |
| R-11 | The camera runs only while the Light detail view or the Light Meter tool is open; the home tile shows the last reading and "Tap to measure". | Done |
| R-12 | No image is saved or shown on the home grid; only the derived number is kept. | Done |

### 4.2 Temperature: device thermal state only

| ID | Requirement | Status |
| --- | --- | --- |
| R-13 | The Thermal State reading shows the phone's own heat level (nominal, fair, serious, critical), labelled "Phone heat", not "temperature". | Done |
| R-14 | Its explainer says plainly that iPhones don't let apps read air temperature, and that this reading is about the phone, not the room. | Done |

Weather data and Bluetooth thermometers were considered and left out of v1; see
[§13 Open questions](#13-open-questions).

### 4.3 Calibrating the two estimates

Neither sound nor light is a measurement, and no iOS API makes one of them into it. What
Readout can do is let somebody who owns a proper meter close the gap on their own phone.

| ID | Requirement | Status |
| --- | --- | --- |
| R-75 | A user can calibrate either estimate against a reference meter: Readout averages its own figure over a few seconds, takes the meter's, and keeps the difference as a sound offset or a light multiplier. A correction larger than the estimate's own spread is refused rather than applied, because it means the two meters were not measuring the same thing. | Done (v0.4.0) — in the Sound meter, the Light meter and Settings; the arithmetic is pure and covered by tests (R-10, R-66, Q-5) |

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
| R-22 | Edit mode (long-press or the Edit button) reorders, hides and restores tiles; the layout is saved on the device. | Done — long-press or Edit; drag to reorder, with VoiceOver move actions since VoiceOver cannot drag, and a Reset order button |
| R-23 | Settings opens as a sheet from the Readings toolbar: units, appearance, recording, haptics, sound calibration offset, About and Privacy. | Done — calibration can be nudged by hand or worked out against a reference meter (R-75), About can bring the first-run explainer back, and Appearance holds the theme and interface size (R-77, R-78) |
| R-77 | **Themes.** A theme sets the appearance Readout asks iOS for, the accent colour, and the colour behind the content. Seven ship: System (the default, which follows the phone's own Light and Dark setting), Dark, Elegant blue, Midnight blue, Sand, Graphite and Forest. | Done (v0.5.0) — a theme changes only those three things: the glass surfaces, tab bar and toolbars take their own tint from the backdrop, so nothing is redrawn by hand and the app stays inside Apple's design language (R-46) |
| R-78 | **Interface size.** Six steps from Smaller to Largest, applied on top of the text size set in iOS Settings rather than replacing it. | Done (v0.5.0) — a step along the system's own type scale, so Form rows, navigation titles, tab bar labels, tiles and the large numeric readouts all grow together and stay laid out properly. From the default text size it spans Small to xxxLarge and stops short of the accessibility sizes; from an accessibility size it steps within them (R-52) |
| R-73 | A one-time explainer on first launch: what Readout measures, that sound and light are estimates, and that nothing leaves the phone. Shown before the first permission prompt. | Done (v0.3.0) |

---

## 6. Sensor detail view

Tapping a tile opens one screen per reading: a large live value, a scrolling chart, quick
stats, and a short explainer with everyday comparisons.

### 6.1 Layout, top to bottom

| ID | Requirement | Status |
| --- | --- | --- |
| R-24 | Live value in large type; three-axis readings show x, y and z side by side, each in its axis colour. | Done |
| R-25 | Live line chart (Swift Charts) with a 10 s window by default, switchable to 1 min and 5 min; pause and resume; tap an axis to hide it. | Done — the window is fixed to the one chosen and labelled as a distance back from now, and the vertical scale fits the samples on screen rather than reaching down to zero |
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
| R-40 | While recording, the screen stays awake and a compact recording bar shows elapsed time, sample count and Stop; tapping the bar opens the running session (R-79). A session stops itself at its limit and warns in the bar from 80% (Q-4). | Done — the bar and the limits are verified; the idle timer cannot be observed in the Simulator |
| R-80 | **The session limit is the user's to choose:** 2 hours (the default, and v0.3.0's behaviour), 6 hours, 12 hours, or no clock at all — running until the volume is down to a reserve Readout will not spend. Each carries a storage ceiling, and a session will not start without the room to finish. A recording keeps the limit it started with. | Done (v0.5.0) — two hours is right as a default, but logging a journey is the obvious thing to want a recording for and plenty of journeys are longer than that (Q-4) |

### 8.2 Leaving the app

| ID | Requirement | Status |
| --- | --- | --- |
| R-41 | A session that cannot carry on in the background stops when the user leaves the app and is saved with an "interrupted" note. Glancing at Control Centre, the app switcher or an incoming-call banner is not leaving: the session carries on regardless. | Done — and a session the app is *killed* during is recovered from its checkpoint on the next launch, rather than deleted as an orphan. Which sessions can carry on is R-82 below |


iOS does not keep an app running because it would like to. The only mechanism that fits a
sensor log is Core Location's background updates: an app with the `location` background mode
and `allowsBackgroundLocationUpdates` set stays alive while it is receiving fixes, with the
blue indicator showing throughout. Everything else the session records then carries on too —
not because each framework has a background mode of its own, but because the process is never
suspended.

That mechanism, not convenience, decides the rules below. Readout says which one applies
*before* the session starts, in the New Recording sheet, rather than letting somebody find out
at the end of a journey.

| ID | Requirement | Status |
| --- | --- | --- |
| R-82 | A session carries on in the background when **all** of: it records at least one position reading (Coordinates, GPS altitude, Speed, Course or Accuracy); location is allowed; and it records neither the microphone nor the camera. Otherwise it stops and saves as before (R-41). The sheet says which, and offers to add Coordinates where that is what is missing. | Partial — see §11.4 |
| R-83 | **The microphone and the camera never run in the background.** Readout declares `location` and no other background mode, and a session recording Sound level or Light is foreground-only however much location it also records. No setting changes this. | Done (v0.5.0) — the rule is enforced in `BackgroundRecording` and covered by tests, including one asserting that `location` is the *only* mode the bundle declares (R-56, R-58) |
| R-84 | Readout asks for When In Use and never for Always. `allowsBackgroundLocationUpdates` works with When In Use and shows the indicator, so Always would buy nothing but a larger permission. It is set only while a qualifying recording runs, and cleared the moment it stops. | Done (v0.5.0) |

Location updates are also stopped from pausing themselves while such a session runs
(`pausesLocationUpdatesAutomatically = false`): iOS pauses them when it decides the device has
stopped moving, which on a train is a log that quietly ends at the first long platform.

### 8.3 Sessions

| ID | Requirement | Status |
| --- | --- | --- |
| R-42 | The Recordings tab lists sessions newest first: auto-generated name (date, time, readings), duration and size. | Done |
| R-43 | A session view shows a chart and min/max/average per reading, with Rename, Delete and Export. | Done — the chart is read back from the session's own CSV, and scaled to it |
| R-76 | A session that logged Coordinates shows its **route**: the track, its length, and the two ends marked. It is plotted from the session's own fixes, which needs no network (R-59); Apple Maps is offered beside it, and stays off until the user asks for it, with the trade spelled out. | Done (v0.5.0) — a local equirectangular projection with a scale bar, north up; the choice is remembered and can be reversed in Settings |
| R-79 | A **running** session can be opened from the recording bar: elapsed time, sample count, size, how much of the limit is left, every reading it is logging as a live tile, and the route building up as the fixes arrive. | Done (v0.5.0) — it takes no leases of its own, so nothing runs because this screen is open that was not already being recorded (R-64). It also says plainly that leaving the app ends the session (R-41, X-4) |

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
| R-46 | Surfaces | Glass tab bar and toolbars; home tiles as glass cards over the background; no custom chrome. | Done — a theme colours that background and nothing else (R-77). Liquid Glass takes its own tint from what is behind it, so one gradient re-colours every card, bar and toolbar without a single one of them being redrawn by hand |
| R-47 | Type | SF Pro throughout; large readouts use monospaced digits so live numbers don't jitter as they change; numeric content transitions animate value changes. | Done |
| R-48 | Icons | One SF Symbol per reading, with symbol effects where they add meaning (for example, the sound tile's symbol reacting to level). | Done |
| R-49 | Colour | System colours with a single accent, which a theme may change; fixed axis colours across the app (x red, y green, z blue); full dark mode and Increase Contrast support. | Done — the axis colours stay fixed whatever the theme, because they are how three traces are told apart rather than decoration, and they carry dash patterns as well (R-52). Dark mode is unchanged for anyone who never opens Appearance: the default theme follows the phone (R-77) |
| R-50 | Motion | Gentle, physical animation (bubble, compass dial); all of it reduced or removed under Reduce Motion. | Done |
| R-51 | Haptics | Level reaching 0°, compass cardinal points, recording start and stop; one switch in Settings turns them off. | Done — recording haptics added in v0.2.0; not feelable in the Simulator |
| R-52 | Accessibility | Dynamic Type on every screen, the large numeric readouts included; VoiceOver reads each value with its unit on request rather than announcing every change; charts expose audio graphs; tools work one-handed. | Done — Dynamic Type, VoiceOver labels, Reduce Motion, and `AXChartDescriptor` audio graphs on the live and session charts. The three axes also carry dash patterns, so they are not told apart by colour alone. From v0.5.0 the large readouts follow Dynamic Type too — they were fixed point sizes, so the one number a reading exists to show was the only thing on screen that did not grow with the text size — and the interface size moves along the same scale rather than magnifying the finished screen (R-78) |
| R-53 | Language | English at launch; units and number formats follow the phone's region. | Done |

---

## 10. Permissions and privacy

Readout collects no data: everything is measured and stored on the phone. There is nothing for
a privacy label to declare, and the manifest in the bundle says so (R-74).

The app makes no network request of its own. One optional feature causes iOS to make one —
Apple Maps fetching tiles for a recorded route — and it is off until the user asks for it
(R-81). Nothing measured or recorded leaves the phone in either state.

| Permission | Needed for | Asked when |
| --- | --- | --- |
| Motion & Fitness | Air pressure, relative altitude, steps, cadence | User first opens one of these readings or adds it to a recording |
| Location (While Using) | Location group; true north on the compass; keeping a journey recording while Readout is in the background (R-82) | User first opens a location reading or the compass |
| Microphone | Sound level, sound meter | User first opens the sound reading or tool |
| Camera | Light reading, light meter | User first opens the light reading or tool |

| ID | Requirement | Status |
| --- | --- | --- |
| R-54 | Permissions are asked only when needed, each preceded by a one-line card explaining why. | Done |
| R-55 | Tiles that lack permission show "Tap to allow"; after a denial they link to the app's page in Settings. | Done |
| R-56 | Microphone audio and camera frames are processed in memory and never saved; only the derived numbers are kept. | Done |
| R-57 | Recordings stay on the device until the user exports them; deleting the app deletes them. | Done — sessions live in Application Support, and deleting one removes its CSV files with it |
| R-58 | iOS shows its orange (microphone) and green (camera) indicators while those sensors are in use, and the blue one while a recording runs in the background; the app never hides or works around any of them. | Done — and the microphone and camera never run in the background at all, so neither of those indicators can ever appear without the app in front (R-83) |
| R-59 | The app makes no network requests of its own: no analytics, no crash reporting SDKs, no remote config, no URLSession anywhere in the source. | Done |
| R-81 | **The single exception, and it is the user's to make.** Showing a recorded route on Apple Maps means iOS fetching map tiles for the ground the route covers, which is a network request. It is off until the user turns it on, from a dialog that says so; the default is a plot drawn from the session's own fixes, which needs nothing. No recording, no coordinate and no file is ever uploaded either way — Readout has no code that could. Settings names the state plainly ("Network requests: None" or "Apple Maps only") and can switch it back off. | Done (v0.5.0) — the privacy manifest is unchanged, because nothing is collected or tracked in either state (R-74, R-76) |
| R-74 | A privacy manifest ships in the bundle: no tracking, no collected data types, and the required-reason APIs the app uses declared — `UserDefaults` (CA92.1) and the free-space check before a recording (E174.1). | Done (v0.3.0) |

---

## 11. Technical notes

The build is native Swift and SwiftUI targeting iOS 26 and later, with no third-party
dependencies.

### 11.1 Stack

| ID | Requirement | Status |
| --- | --- | --- |
| R-60 | SwiftUI with the Observation framework; Swift Charts for all charts; MapKit only for the optional route map (R-76, R-81). The offline route plot is a `Canvas`, so the default path pulls in no map framework at runtime. | Done |
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
| R-66 | Sound | Audio session in measurement mode to avoid automatic gain; RMS level converted to dBFS, then to an estimated dB with a per-model calibration offset. | Partial — the per-model offset is applied from `DeviceCalibration` beneath the user's own, which the guided calibration can now work out (R-75), but the table is empty until models are measured (R-72). Interruptions, route changes and a media-services reset are handled: the meter and the detail view both say the reading is paused rather than holding a stale number |
| R-67 | Light | Low-resolution capture session read only for exposure metadata; front and rear cameras need separate calibration. | Done |
| R-68 | Proximity | Turning on proximity monitoring blanks the screen when something covers the sensor, so it runs only inside its detail view, behind a "Start test" button. | Done |
| R-69 | Heading | Shows the system calibration prompt when heading accuracy is poor. | Done |
| R-70 | Pedometer | Shows today's totals from the system, plus live cadence and pace while walking. | Done |

### 11.4 Testing

| ID | Requirement | Status |
| --- | --- | --- |
| R-71 | Most sensors don't work in the Simulator, so the sensor service sits behind a protocol with a mock that replays synthetic data for previews and UI tests. | Done — from v0.4.0 **every** reading comes from the mock there, not only the ones a framework admits to lacking: Core Location reports itself available and then never produces a fix, which left the location group waiting for ever. The Simulator also skips the permission gate, since there is no real sensor to protect and no way to answer a Motion & Fitness prompt |
| R-72 | Calibration offsets for sound and light need checking on real devices against a reference meter. | Open — needs hardware |
| R-85 | Background recording needs checking on a real iPhone. | Open — needs hardware. What the Simulator **does** prove: a qualifying session is no longer ended by backgrounding (it ran 94 s across a background period and saved normally rather than interrupted), and setting `allowsBackgroundLocationUpdates` does not raise, so the background mode is correctly declared. What it **cannot** prove: that sampling continues throughout. The same run left 14 s and 46 s gaps in its CSVs, because the Simulator has no real fixes arriving and suspends the process anyway. On a device the fixes are what keep it scheduled — which is the whole mechanism, and exactly the part a build machine cannot exercise |

---

## 12. Milestones

| Milestone | Contents | State |
| --- | --- | --- |
| **v0.1.0 — Readings & tools** | App shell and three tabs; all 19 readings with live providers; tile grid with all four states; detail views with charts, stats, comparisons and explainers; all four instrument tools; Settings; permission flow; mock source for Simulator and previews; 40 unit tests | Shipped — built and run in the Simulator; **not yet verified on physical hardware** |
| **v0.2.0 — Recording & export** | §8 in full: recording sessions, sample rates, recording bar, session list and detail, SwiftData metadata, CSV writing and share-sheet export, Record buttons wired up (R-6, R-29, R-36–45, R-51, R-57, R-61) | Shipped — recorded, listed, charted and exported in the Simulator against the synthetic source; **not yet verified on physical hardware** |
| **v0.3.0 — Release readiness** | App icon as an Icon Composer document; the defects a full-source audit turned up, including one that could delete every recording and one that could crash the Sound meter; drag-to-reorder (R-22), chart audio graphs (R-52), the calibration mechanism (R-10, R-66), first-run explainer (R-73); recording limits (Q-4) and crash recovery; privacy manifest (R-74), licence, CI and `docs/RELEASE.md` | Shipped — built and tested in the Simulator; **not yet verified on physical hardware** |
| **v0.4.0 — Honest estimates & polish** | Guided calibration against a reference meter (R-75); charts scaled to their data with a labelled time axis (R-25, R-43); portrait only (R-1); tiles that grow with Dynamic Type (R-52); the empty-grid state (R-22); and the defects a lifecycle pass turned up — a permission granted in-app starting nothing (R-54), the sound reading hidden on a phone that has a microphone (R-7), a blocking location check at launch, the bubble leaving its circle (R-32), and the whole location group waiting for ever in the Simulator (R-71) | Shipped — built and tested in the Simulator; **not yet verified on physical hardware** |
| **v0.5.0 — Logging a journey, and making it yours** | What a recording is for: a running session you can watch (R-79), the route a session logged (R-76), and a limit long enough for the journey (R-80). Background recording for a session that records the user's position, with the microphone and camera permanently excluded from it (R-82–R-84). Plus the customisation the app had none of — seven themes (R-77) and an interface size (R-78) — and the defects a full audit turned up: a location permission granted in-app that left every location reading gated, the compass tick landing halfway between north and east, comparisons claiming "about the same as" however far away, large readouts ignoring Dynamic Type, and the live chart copying its whole 3,000-sample history on every redraw | Shipped — built and tested in the Simulator; **not yet verified on physical hardware** |
| **v1.0 — Verified on hardware** | What is left is what a build machine cannot do: on-device verification of every reading, the audio-interruption and 50 Hz checks, and the sound and light baselines measured against a reference meter. The checklist is [`docs/RELEASE.md`](RELEASE.md) §3. There is no plan to publish on the App Store, so nothing here waits on a submission | Planned |

---

## 13. Open questions

Decisions for the next round of refinement. The **Draft 1 answer** column records the
provisional choice v0.1.0 ships with; none of them is settled.

| # | Question | Draft 1 answer |
| --- | --- | --- |
| Q-1 | Home grid default: show all 19 readings, or a starter set of about 8 with the rest under Edit? | All 19, grouped |
| Q-2 | Compass and level tiles: open the detail view or jump straight to the tool? | Detail view; tools live in their own tab |
| Q-3 | Leaving the app mid-recording: stop and save, or pause and resume on return? | Stop and save with an "interrupted" note |
| Q-4 | Maximum recording length and a storage cap per session? | **Settled in v0.3.0, widened in v0.5.0:** two hours and 100 MB remain the default, but they are now a choice — 6 hours, 12 hours, or no clock at all down to a 500 MB reserve. The reasoning behind the cap was that a session must not quietly fill the device, and a storage ceiling still enforces that; the clock was never the part that protected anything, and a journey is the obvious thing to log (R-80) |
| Q-5 | Sound meter calibration: fixed per-model offsets, user calibration against a reference meter, or both? | **Settled in v0.4.0: both.** A per-model baseline from `DeviceCalibration` underneath, and the user's own correction on top, worked out by the guided calibration (R-75). The per-model table stays empty until models are measured (R-72) |
| Q-6 | Recordings: device-only, or iCloud sync later? | Device-only |
| Q-7 | Temperature in a later version: nearby weather (labelled), Bluetooth thermometers, or neither? | Neither in v1 |
| Q-8 | Widgets, Control Centre controls or Shortcuts actions ("What's the air pressure?") in v1.1? | Undecided |
| Q-9 | iPad or Apple Watch later, given their different sensor sets? | Undecided |
| Q-10 | Name check: is "Readout" available on the App Store, and what does the icon look like? | **Settled.** The icon shipped in v0.3.0 — a rising trace with a live point, the mark the tiles already draw, as an Icon Composer document so iOS renders all four appearances. The name check is moot: Readout is shared as source and run from Xcode, not published |
| Q-12 | Recording in the background, so a journey survives the phone being pocketed? | **Settled in v0.5.0, within the limits iOS imposes.** A session that records the user's position carries on, because Core Location's background updates are the mechanism that allows it (R-82). A session without one cannot — there is no mechanism — and the app says so before it starts rather than pretending. The microphone and the camera are excluded by choice, not by limitation (R-83). Readout asks for When In Use, never Always (R-84) |
| Q-13 | Should a theme be able to change the axis colours, or the caution colours? | **No, for now.** x red, y green, z blue is how three traces are told apart, not decoration, and orange at 85 dB is a warning. A theme colours the background and the accent (R-49, R-77) |
| Q-11 | Re-check the latest iOS SDK before building, in case Apple has opened up light or temperature data. | Checked 2026-10-18 against the iOS 27 SDK: still no ambient-light or temperature API |
