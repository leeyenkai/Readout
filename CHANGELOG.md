# Changelog

All notable changes to Readout are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). `R-nn` references point at
requirement IDs in [`docs/SPEC.md`](docs/SPEC.md).

## [Unreleased]

## [0.6.0] — 2026-10-23

**Black by default, a phone you can see turn, and the defects a real iPhone would have found.**
Readout now opens in true black with a blue accent, moves the way an instrument should, and
looks the same from one screen to the next. A new Attitude tool draws the phone in 3D, turning
as the real one does. And a correctness audit turned up a set of defects that only a physical
iPhone would have shown — a first journey recording that quietly dropped its location, a
background recording that left the microphone running, GPS fixes thrown away. Built and tested
in the Simulator; the on-device pass that gates v1.0 is still outstanding
([`docs/RELEASE.md`](docs/RELEASE.md) §3).

### Added

- **Attitude: your phone in 3D.** A new tool draws a lit, three-dimensional phone that turns
  as yours does, from Core Motion's attitude, with its x, y and z axes in the colours every
  chart uses. Give the phone a push and the model sways on a spring and settles back, with an
  arrow showing the push. It deliberately does not claim to track the phone through space:
  working position out from an accelerometer turns a tiny error into metres of imaginary travel
  within seconds, and the explainer says so (P-2). Drag to look at it from another side; Hold
  freezes it, Recentre turns it to face the way you are holding the phone. The Orientation
  reading links to it. Built with RealityKit from shapes rather than a model file, so there is
  no asset to ship and no particular phone being copied (R-86).
- **The interface moves.** Tiles, tools and recordings zoom open from where they were tapped;
  the grid settles in as the app opens; slow readings roll their digits; states cross-fade
  rather than snap; the welcome screen draws the app's own mark on; a saved recording's route
  draws itself; a recording ends with a "Recording saved" confirmation. Every one of them stands
  down under Reduce Motion (R-50).
- **Instruments that look the part.** The spirit level is a lit glass vial with a real bubble
  that pulses as it reaches level and morphs between the flat and edge vials; the compass card
  keeps its lettering upright and marks a locked bearing with an arc; the sound meter gains a
  level bar with a peak-hold tick and a symbol that fills with the level; the light meter shows
  the spot it is metering and flips between cameras (R-32–R-35, R-48).
- **Hold on the sound meter**, like the level and the light meter (R-34).
- **The level's zero is kept**, per mode and per edge, rather than lost when you leave (R-32).

### Changed

- **True black by default.** The Dark theme — true black, kind to an OLED screen, with iOS's
  own dark-mode blue — is the default, whatever the phone's own appearance. System is still a
  choice, and anybody who picked it keeps it. The launch screen is black to match (R-77).
- **One design language.** Every card, header, statistic, badge and control row is built from
  the same few pieces, so a card on one screen is the same card on the next; instrument switches
  that showed their state as a button title ("Fast", "True north", "Rear camera") are segmented
  controls; "Reset" means the same thing everywhere; Form rows on the tinted themes take the
  theme's colour instead of grey slabs (R-46).
- **The compass needs no permission.** Only true north needs Location, and the compass asks for
  it there, carrying on against magnetic north until it is allowed (SPEC §3, reading 5).
- **The Record button opens a running recording** instead of sitting disabled with nothing to
  say why, and the Recordings tab says when your first recording is running (R-29, R-79).
- **Settings that change what a recording means are fixed while it runs**: Include gravity,
  true north, the sound response and both calibrations (R-30, R-45).
- Each tile now follows only its own reading, so a new sample redraws one tile rather than the
  whole grid; the live chart's scale settles instead of jumping with every new extreme; the
  compass, level and calibration sheets cannot take a second lease on reappearing (R-25, R-64,
  R-65).
- Copy: "recording" throughout rather than "session", sentence case, shorter Settings footers,
  and an About section that describes the app rather than calling it a hobby project.

### Fixed

- **A first journey recording silently dropped its location.** Core Location's permission
  request returns before the prompt is answered, so Coordinates was left out, the recording was
  judged foreground-only, and locking the phone ended it. The request is now awaited properly —
  which also fixes allowing location from a reading's own screen starting nothing (R-38, R-54,
  R-82).
- **A recording carrying on in the background left the open screen's sensors running — the
  microphone included.** Only the readings the recording logs keep running now (R-58, R-64,
  R-83).
- **Batched location fixes were thrown away**, leaving gaps in a journey's CSV and route; and
  **replayed fixes were written again** each time another screen took a lease (R-45, R-76).
- **"Until storage runs out" stopped at about half** the free space, counting what it had
  written twice (R-80).
- **Partly refused permissions were dropped without a word**; New Recording now asks before
  starting without them (R-38).
- **Angles were averaged as plain numbers**: a heading either side of north averaged to south.
  Heading, course, yaw and roll are now summarised round the circle (R-26, R-43).
- **No course or speed was recorded as 0** — due north, standing still — rather than as no
  value (R-45).
- **The spirit level's bubble sank on one axis and rose on the other**, on a real phone; standing
  the phone on its long edge read ±90°; and zeroing on an edge shifted the flat reading (R-32).
- **The compass dial spun the long way round** when the heading crossed north (R-33).
- **Device motion waited for ever without Location** on a phone that refused it, for want of a
  true-north reference none of the motion readings need; and a later 10 Hz lease could slow a
  50 Hz recording (R-39, R-63).
- **The sound level started about 20 dB low** after every start, and the meter restarted the
  microphone on its own route changes; **camera interruptions** left a stale lux figure on screen
  (R-34, R-35, R-66).
- **"Since you opened this" reached back to launch** (R-26).
- **Leaving the Sound or Light meter by switching tab could start the microphone or camera
  again** behind you, as giving the lease back retriggered the meter's own activation; and
  leaving the Light meter mid-recording switched the camera the recording was logging (R-64,
  R-67).
- A recovered recording could be lost if saving it failed; the first recording skipped its
  free-space check; a recording with no samples vanished silently; deleting a recording from
  its own screen could read a deleted object; a blank rename was accepted and ignored.
- Apple Maps could be switched on from Settings without the dialog the route panel shows (R-81).
- The Settings footer still said leaving the app always stops a recording (R-82).
- Sheets came up in the asset catalogue's green rather than the theme's accent; the comparison
  marker drew a black ring on the tinted themes; coordinates could print `59′ 60.0″`; a value
  rounding to zero printed as "-0.00".

## [0.5.0] — 2026-10-20

**Logging a journey, and making the app yours.** What a recording is actually for — watching a
session as it runs, and seeing where it went — plus the customisation Readout had none of, and
the defects a full-source audit turned up. Built and tested in the Simulator; the on-device
pass that gates v1.0 is still outstanding ([`docs/RELEASE.md`](docs/RELEASE.md) §3).

### Added

- **A recording of a journey carries on when you leave the app.** A session that records your
  position keeps running if you lock the phone or switch apps, which is what logging a journey
  actually requires. iOS shows the blue location indicator for as long as it does.

  The rules come from the only mechanism iOS offers — Core Location's background updates — so
  Readout says which one applies before the session starts rather than letting you find out at
  the end of a train journey: a session needs a position reading (the sheet offers to add
  Coordinates if it has none) and location has to be allowed. **The microphone and the camera
  never run in the background at all**, by choice rather than limitation: `location` is the
  only background mode Readout declares, so a session recording Sound level or Light stays
  foreground-only however much location it also records. Readout asks for When In Use and
  never Always (R-82, R-83, R-84, Q-12).

  *Not yet verified on a physical iPhone.* The Simulator proves the session is no longer ended
  by backgrounding, and that the entitlement is correctly declared — but it has no real fixes
  arriving to keep the process scheduled, so it cannot show that sampling continues throughout
  (R-85, SPEC §11.4).

- **A running session can be watched.** Tapping the recording bar opens it: elapsed time,
  sample count, size, how much of the limit is left, a live tile for every reading being
  logged, and the route building up as the fixes arrive. Start a recording at the top of a
  journey and this is the screen to leave open. It takes no sensor leases of its own, so
  nothing runs because this screen is open that was not already being recorded (R-79, R-64).

- **A recorded session shows its route.** Where a session logged Coordinates, the session view
  draws the track with its two ends marked, its length, and a scale bar — plotted from the
  session's own fixes in a local equirectangular projection, north up. It needs no network and
  no map server, so it works with the radio off (R-76, R-59).

- **Apple Maps, behind an opt-in.** The route can be shown on Apple Maps instead. It is off
  until asked for, from a dialog that says what the trade is: Apple Maps downloads its tiles,
  so this is the one thing in Readout that uses the network. No recording and no coordinate is
  uploaded either way. Settings names the state — "Network requests: None" or "Apple Maps
  only" — and can switch it back off (R-81).

- **Themes.** Seven: System (the default, following the phone's own Light and Dark setting),
  Dark, Elegant blue, Midnight blue, Sand, Graphite and Forest. A theme sets the colour behind
  the readings and the accent on top; Liquid Glass does the rest, because every card, tab bar
  and toolbar takes its own tint from what is behind it. Nothing is redrawn by hand (R-77,
  R-46).

- **An interface size,** six steps from Smaller to Largest, in Settings › Appearance. It is a
  step along the system's own type scale rather than a magnification of the finished screen, so
  Form rows, navigation titles, tab bar labels, tiles and the big readouts all grow together
  and stay laid out properly — and it composes with the text size set in iOS Settings instead
  of overruling it (R-78, R-52).

- **The session limit is yours to raise.** Two hours and 100 MB are still the default, but a
  journey is the obvious thing to log and plenty of journeys are longer: 6 hours, 12 hours, or
  no clock at all, down to a 500 MB reserve Readout will not spend. A session will not start
  without the room to finish, and a recording already running keeps the limit it started with
  (R-80, Q-4).

### Changed

- **"Ready" means ready to share, not ready to submit.** There is no plan to put Readout on the
  App Store, so `docs/RELEASE.md` is now about handing it to somebody: what they need to build
  it, sign it with their own team and run it on their own iPhone, and what to tell them about
  the estimates. The on-device checklist that decides whether the numbers can be trusted is
  unchanged, and the App Store paperwork is kept in a section of its own in case that decision
  ever changes. The v1.0 milestone and **Q-10** follow (SPEC §12, §13).

- **The Light meter's preview says when there is nothing to show.** A device with no camera —
  the Simulator — drew an empty black panel beside a working reading, which looks like a fault
  rather than the absence of a camera (R-35, R-71).

### Fixed

- **A location permission granted inside the app started nothing.** Core Location's request
  returns before the prompt is answered, so the status Readout cached a moment later was still
  "not determined" — and every location reading stayed behind its "Tap to allow" card, with the
  provider never started, until the app was sent to the background and brought back. The
  provider now reports the answer when it arrives and the hub starts what was waiting on it.
  The v0.4.0 fix for this only ever covered the three permissions whose request can be awaited
  (R-54, R-55).

- **The compass's haptic tick landed halfway between north and east.** It followed the
  *nearest* cardinal point, which changes as the heading crosses 45°, 135°, 225° and 315° — so
  the tap meant to mark north was felt 45° away from it. It now fires on the point itself
  (R-51, R-33).

- **"About the same as" was claimed however far away the comparison was.** At 50% the battery
  reading called itself about the same as the Low Power Mode prompt at 20%, and a phone sitting
  still about the same as a car pulling away. A value now has to sit close to a reference —
  measured along the bar, so one rule serves the logarithmic light scale too — or nothing is
  claimed (P-2, R-27).

- **The large readouts ignored Dynamic Type.** The dB figure on the Sound meter, the heading on
  the compass and the value at the top of every detail view were fixed point sizes, so the one
  number a reading exists to show was the only thing on screen that did not grow with the text
  size. They now scale with it, capped so an accessibility size cannot push a 64-point figure
  off the screen (R-52).

- **The live chart copied its whole history on every redraw.** Reading a ten-second window
  materialised all 3,000 samples in the ring and then filtered them — at display rate, for each
  of three axes. It now walks back from the newest sample and stops at the edge of the window
  (R-65).

- **Copying a value tapped twice.** The haptic fired on the "Copied" badge fading out as well
  as on the copy (R-31, R-51).

- **The Welcome sheet's Start button answered taps outside itself.** Its padding was applied
  outside the button style, so the tap target was taller than the glass capsule (R-73).

- **A second calibration taken straight after the first corrected for a figure that was never
  shown.** The reading is averaged over five seconds, and those five seconds still held samples
  taken under the old correction — a different scale. Applying or clearing a correction now
  throws that history away, so the average restarts from what the phone is actually reporting
  (R-75).

## [0.4.0] — 2026-10-19

**Honest numbers, and the polish a release needs.** A calibration a user can actually carry
out, charts that show the reading rather than the axis, and the defects a pass over the sensor
lifecycle turned up — two of which would only ever have shown themselves on a real iPhone.
Built and tested in the Simulator; the on-device pass that gates v1.0 is still outstanding
(`docs/RELEASE.md` §2).

### Added

- **Calibrate against a reference meter (R-75).** Hold a sound level meter or a lux meter
  beside the phone, type what it reads, and Readout works the correction out itself: averaged
  over five seconds rather than caught on the instant, rounded no finer than the estimate
  deserves, and refused outright when the two figures are too far apart to be a calibration
  rather than a mistake. It reaches the sensor through an ordinary lease, so it works the same
  from the Sound meter, the Light meter and Settings. This completes the user's half of
  **Q-5**; the per-model table still needs hardware (R-10, R-66, R-72).
- **A time axis on the live chart.** The window is fixed to the one the picker names and
  labelled as a distance back from now — "−10 s", "−5 s" — so the trace scrolls at a constant
  scale instead of the axis stretching to whatever has arrived (R-25).
- **An empty state for the grid.** Hiding every tile is something edit mode can do, so the
  grid now says so and offers to bring them back, rather than showing nothing at all (R-22).
- **Settings:** a way back to the first-run explainer, the model identifier a calibration
  would be filed under, and a Clear calibration button once a correction has been made
  (R-23, R-73).
- **Unit tests** — 18 more (127 in all), over the calibration arithmetic and its refusals,
  reading a typed figure in a region that writes decimals with a comma, the chart's relative
  time labels, and the bubble's vector clamp.

### Changed

- **Charts scale to their data.** Both the live chart and the session charts fitted their
  vertical axis around zero, so air pressure — which lives between about 1,000 and 1,030 hPa —
  drew as a dead flat line across the middle of an axis that ran from nothing. They now fit
  the samples on screen, with a margin (R-25, R-43).
- **Portrait only.** R-1 has always said portrait-first; the build allowed landscape anyway,
  on screens that were never laid out or tested for it — and standing the phone on its edge to
  use the level would rotate the interface out from under the measurement. The supported
  orientations now match the specification.
- **Tiles grow with the text.** The card had a fixed height and clipped a reading's name to a
  single line, so at accessibility text sizes half the grid read "Accele…". The height is now
  a scaled metric and a name may take two lines (R-52).
- **Coordinates sit on two lines on their tile**, latitude over longitude. One line of decimal
  degrees does not fit half the width of the screen, and the tile was cutting the longitude off
  mid-digit (R-16).
- **In the Simulator every reading comes from the synthetic source.** It used to stand in only
  where a framework admitted the hardware was missing, and Core Location does not: it reports
  itself available, then never produces a fix, so the location group and the compass's position
  panel waited for ever. The whole interface is now demoable there, and every value carries its
  "Simulated" note (R-71).

### Fixed

- **A permission granted inside the app did not start anything.** A view takes its lease when
  it appears, before the prompt is answered, so granting access left the lease outstanding and
  the provider stopped — the compass sat blank until it was left and opened again, and so did
  any tile on the grid. Permission requests now go through the hub, which starts whatever was
  waiting on the answer (R-54, R-64).
- **The sound reading could be hidden on a phone that has a microphone.** Availability was
  decided by `AVAudioSession.availableInputs`, which answers only for the session's current
  category — a playback one until the meter starts. Every iPhone has a microphone; whether it
  can be opened is reported by the meter's own status instead (R-7, R-34).
- **Location support was resolved with a blocking call at launch.** `locationServicesEnabled()`
  is documented as blocking, and the hub asks about all 19 readings while the first frame is
  being built. Services switched off device-wide is a refused permission, which is what the
  app now treats it as, rather than missing hardware (R-7).
- **The spirit level's bubble could leave its circle.** The two axes were clamped separately,
  so a diagonal tilt put the bubble √2 of the way out — through the corner of the ring it is
  supposed to sit inside. It is clamped as a vector now, keeping its direction (R-32).
- **The Sound meter's peak was the one figure not taken from the shared history**, so it
  disagreed with the average and the quietest reading — and showed 0 whenever the level came
  from anywhere but the live audio engine. All three now come from the same buffer the chart
  draws (R-34).
- **A reading that has stopped arriving says so.** The microphone being taken by a call left
  the last number on screen in the Sound level detail view; it now reads "Paused", as the Sound
  meter already did (P-2, R-66).
- **VoiceOver read coordinates in decimal degrees** whatever the user had chosen in Settings
  (R-8, R-52).
- **CI could not select a toolchain.** The workflow pointed at `/Applications/Xcode_27.app`,
  which the runner image does not have, and then picked the newest iPhone device type
  outright — which `simctl create` rejects when the newest runtime cannot run it. It now
  selects the newest installed Xcode and takes the device from the chosen runtime's own
  supported list, through `scripts/pick-simulator.py`. The toolchain floor is Xcode 26, not
  the 27 the app is developed on: GitHub's `macos-26` image tops out at Xcode 26.6, and
  Readout only needs the iOS 26 SDK.

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

[Unreleased]: https://github.com/leeyenkai/Readout/compare/v0.6.0...HEAD
[0.6.0]: https://github.com/leeyenkai/Readout/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/leeyenkai/Readout/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/leeyenkai/Readout/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/leeyenkai/Readout/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/leeyenkai/Readout/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/leeyenkai/Readout/releases/tag/v0.1.0
