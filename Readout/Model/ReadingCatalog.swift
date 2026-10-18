import Foundation

/// The 19 readings of v1, with their copy, units and comparison scales (SPEC §3).
///
/// This is the only place a reading is described. The grid, the detail view and the
/// permission flow all read from here.
enum ReadingCatalog {
    static let all: [ReadingDescriptor] = [
        // MARK: Motion

        ReadingDescriptor(
            id: .acceleration,
            name: "Acceleration",
            group: .motion,
            symbol: "arrow.up.and.down.and.arrow.left.and.right",
            source: "Core Motion, accelerometer",
            channels: [
                ReadingChannel("X", .acceleration, axis: .x),
                ReadingChannel("Y", .acceleration, axis: .y),
                ReadingChannel("Z", .acceleration, axis: .z),
            ],
            tile: .magnitude(label: "Total"),
            explainer: Explainer(
                what: "The accelerometer measures how hard the phone is being pushed along each of its three axes. With gravity removed you are seeing only movement; include gravity and a phone lying still reads 1 g downwards.",
                precision: "Read straight from the accelerometer through Core Motion, at up to a few hundred samples a second. Small readings while the phone sits still are sensor noise, not movement.",
                tryThis: "Hold the phone flat and drop your hand a few centimetres: Z dips as you fall, then spikes as you stop."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(0.3, "Car pulling away"),
                    .init(0.8, "Hard braking"),
                    .init(1, "Gravity at rest"),
                    .init(3.5, "Roller coaster"),
                ],
                span: 0...4
            )
        ),

        ReadingDescriptor(
            id: .rotationRate,
            name: "Rotation rate",
            group: .motion,
            symbol: "gyroscope",
            source: "Core Motion, gyroscope",
            channels: [
                ReadingChannel("X", .angularVelocity, axis: .x),
                ReadingChannel("Y", .angularVelocity, axis: .y),
                ReadingChannel("Z", .angularVelocity, axis: .z),
            ],
            tile: .magnitude(label: "Total"),
            explainer: Explainer(
                what: "The gyroscope measures how fast the phone is turning about each axis, in degrees per second. It says nothing about which way up the phone is — only how quickly that is changing.",
                precision: "A vibrating-structure gyroscope, accurate to a fraction of a degree per second. It drifts slowly, which is why orientation combines it with the accelerometer.",
                tryThis: "Spin on an office chair with the phone flat in your lap and watch Z climb; one lazy turn a second is about 360 °/s."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(30, "Slow pan"),
                    .init(180, "Half a turn a second"),
                    .init(360, "One turn a second"),
                    .init(900, "A quick flick"),
                ],
                span: 0...1_000
            )
        ),

        ReadingDescriptor(
            id: .orientation,
            name: "Orientation",
            group: .motion,
            symbol: "rotate.3d",
            source: "Core Motion, device motion",
            channels: [
                ReadingChannel("Pitch", .angle, axis: .x),
                ReadingChannel("Roll", .angle, axis: .y),
                ReadingChannel("Yaw", .angle, axis: .z),
            ],
            tile: .channel(0),
            explainer: Explainer(
                what: "How the phone is tilted: pitch is nose up or down, roll is side to side, and yaw is the direction it is pointing. iOS works these out by combining the accelerometer, gyroscope and magnetometer.",
                precision: "Pitch and roll are steady to about a tenth of a degree because gravity anchors them. Yaw drifts unless the magnetometer is calibrated — the Compass tool is the better tool for direction.",
                tryThis: "Stand the phone upright against a wall: pitch should read close to 90°."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(0, "Flat"),
                    .init(45, "Propped up"),
                    .init(90, "Upright"),
                ],
                span: -90...90
            )
        ),

        ReadingDescriptor(
            id: .magneticField,
            name: "Magnetic field",
            group: .motion,
            symbol: "bolt.horizontal.circle",
            source: "Core Motion, magnetometer",
            channels: [
                ReadingChannel("X", .magneticFlux, axis: .x),
                ReadingChannel("Y", .magneticFlux, axis: .y),
                ReadingChannel("Z", .magneticFlux, axis: .z),
            ],
            tile: .magnitude(label: "Strength"),
            explainer: Explainer(
                what: "The magnetometer measures magnetic field strength in microtesla. Most of what it sees is the Earth's own field, which is why it doubles as a compass — but any magnet or motor nearby will swamp it.",
                precision: "Raw, uncalibrated readings from the magnetometer, including whatever the phone's own electronics contribute. The Earth's field is about 25–65 µT depending on where you are.",
                tryThis: "Wave a fridge magnet past the top of the phone and watch the total jump into the hundreds."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(25, "Earth, near the equator"),
                    .init(50, "Earth, mid-latitudes"),
                    .init(500, "Fridge magnet, close"),
                ],
                span: 0...600
            )
        ),

        ReadingDescriptor(
            id: .heading,
            name: "Heading",
            group: .motion,
            symbol: "location.north.line",
            source: "Core Location, heading",
            channels: [ReadingChannel("Heading", .angle)],
            permission: .locationWhenInUse,
            tile: .channel(0),
            explainer: Explainer(
                what: "Which way the top of the phone is pointing, in degrees clockwise from north. Magnetic north is what the magnetometer sees; true north is the geographic pole, and finding it needs your location.",
                precision: "Typically within a few degrees once calibrated. Accuracy drops near metal, speakers and magnetic cases — iOS asks you to wave the phone in a figure of eight when it needs a fresh calibration.",
                tryThis: "Point the phone along a street you know runs north–south and see how close to 0° or 180° it gets."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(0, "North"),
                    .init(90, "East"),
                    .init(180, "South"),
                    .init(270, "West"),
                ],
                span: 0...360
            )
        ),

        // MARK: Environment

        ReadingDescriptor(
            id: .airPressure,
            name: "Air pressure",
            group: .environment,
            symbol: "barometer",
            source: "Core Motion, altimeter (barometer)",
            channels: [ReadingChannel("Pressure", .pressure)],
            permission: .motionFitness,
            tile: .channel(0),
            explainer: Explainer(
                what: "The barometer measures the weight of the air above the phone. It falls as you climb and as weather fronts move in, which is how the phone helps count floors.",
                precision: "Sensitive to a fraction of a hectopascal — enough to notice a lift ride. It is absolute pressure where you are, not the sea-level figure a weather forecast quotes.",
                tryThis: "Take a lift up a few floors and watch the number fall by roughly 1 hPa every 8 metres."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(780, "Airliner cabin"),
                    .init(900, "1,000 m up"),
                    .init(990, "Stormy low"),
                    .init(1_013, "Sea level average"),
                ],
                span: 700...1_060
            )
        ),

        ReadingDescriptor(
            id: .relativeAltitude,
            name: "Relative altitude",
            group: .environment,
            symbol: "arrow.up.arrow.down",
            source: "Core Motion, altimeter",
            channels: [ReadingChannel("Change", .altitude)],
            permission: .motionFitness,
            tile: .channel(0),
            explainer: Explainer(
                what: "How far up or down you have moved since this reading started, worked out from the change in air pressure. It is a change, not a height above sea level — for that, use GPS altitude.",
                precision: "Good to about a metre over short periods, which is why it can count floors. Weather changes make it drift over hours, so it resets each time it starts.",
                tryThis: "Start it at the bottom of a staircase and walk up: each storey is about 3 metres."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(3, "One storey"),
                    .init(10, "Three storeys"),
                    .init(30, "Ten storeys"),
                ],
                span: -30...30
            )
        ),

        ReadingDescriptor(
            id: .soundLevel,
            name: "Sound level",
            group: .environment,
            symbol: "waveform",
            source: "AVFoundation, microphone level metering",
            channels: [ReadingChannel("Level", .soundPressure)],
            activation: .onDemand,
            permission: .microphone,
            tile: .channel(0),
            explainer: Explainer(
                what: "How loud it is around you, in decibels. Decibels are logarithmic: every 10 dB is roughly a doubling of how loud something seems, and 85 dB is where long exposure starts to risk your hearing.",
                precision: "An estimate. Readout measures the microphone's signal level and converts it with a fixed offset, so it is useful for comparisons, not for anything official. A proper sound level meter is calibrated against a reference tone.",
                tryThis: "Measure the quietest room you can find, then your kitchen with the tap running — the gap is usually 30 dB or more."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(30, "Whisper"),
                    .init(40, "Quiet library"),
                    .init(60, "Conversation"),
                    .init(85, "Heavy traffic", caution: true),
                    .init(100, "Concert", caution: true),
                ],
                span: 20...120
            ),
            estimateNote: "Microphone estimate, uncalibrated"
        ),

        ReadingDescriptor(
            id: .light,
            name: "Light",
            group: .environment,
            symbol: "sun.max",
            source: "AVFoundation, camera exposure data",
            channels: [ReadingChannel("Illuminance", .illuminance)],
            activation: .onDemand,
            permission: .camera,
            tile: .channel(0),
            explainer: Explainer(
                what: "How bright the light falling on the camera is, in lux. iPhones have an ambient light sensor, but iOS keeps it to itself — so Readout works brightness out from the camera's exposure settings instead.",
                precision: "An estimate, and the reason the value carries a “≈”. It is derived from ISO, shutter speed and aperture, so it depends on where the camera is pointed and needs calibrating per phone model.",
                tryThis: "Point it at a window, then at the floor of the same room — daylight is usually ten to a hundred times brighter than you would guess."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(1, "Moonlight"),
                    .init(50, "Dim living room"),
                    .init(400, "Office"),
                    .init(1_000, "Overcast day"),
                    .init(100_000, "Direct sun"),
                ],
                span: 0.1...100_000,
                logarithmic: true
            ),
            estimateNote: "Camera estimate"
        ),

        // MARK: Location

        ReadingDescriptor(
            id: .coordinates,
            name: "Coordinates",
            group: .location,
            symbol: "mappin.and.ellipse",
            source: "Core Location",
            channels: [
                ReadingChannel("Latitude", .angle),
                ReadingChannel("Longitude", .angle),
            ],
            kind: .coordinates,
            permission: .locationWhenInUse,
            tile: .coordinates,
            explainer: Explainer(
                what: "Where you are, as latitude and longitude. The phone works it out from GPS and the other satellite systems, helped along by known Wi-Fi networks and mobile masts.",
                precision: "Typically within 5 metres outdoors with a clear view of the sky, and much worse indoors or between tall buildings. The Accuracy reading tells you how much to trust it.",
                tryThis: "Note your coordinates indoors, then step outside and watch the accuracy figure tighten up."
            )
        ),

        ReadingDescriptor(
            id: .gpsAltitude,
            name: "GPS altitude",
            group: .location,
            symbol: "mountain.2",
            source: "Core Location",
            channels: [ReadingChannel("Altitude", .altitude)],
            permission: .locationWhenInUse,
            tile: .channel(0),
            explainer: Explainer(
                what: "Your height above mean sea level, from the satellites. Unlike relative altitude, this is an absolute figure — but it is the least precise thing GPS gives you.",
                precision: "Often out by 10 metres or more, because satellite geometry is poor in the vertical direction. The barometer is better at measuring a change in height; GPS is better at where you are.",
                tryThis: "Compare it against a map height for where you are standing — being 10 metres out is perfectly normal."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(0, "Sea level"),
                    .init(100, "Low hill"),
                    .init(500, "High ground"),
                    .init(2_000, "Mountain"),
                ],
                span: -100...3_000
            )
        ),

        ReadingDescriptor(
            id: .speed,
            name: "Speed",
            group: .location,
            symbol: "speedometer",
            source: "Core Location",
            channels: [ReadingChannel("Speed", .speed)],
            permission: .locationWhenInUse,
            tile: .channel(0),
            explainer: Explainer(
                what: "How fast you are moving over the ground, measured by the shift in the satellites' signals rather than by timing one position against the next.",
                precision: "Good to a few tenths of a metre per second when moving. Standing still it can read a stubborn 1 or 2 km/h, and indoors it often reports nothing at all.",
                tryThis: "Check it on a bus or train — the number settles far more smoothly than it does when you are walking."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(1.4, "Walking"),
                    .init(2.8, "Jogging"),
                    .init(5.6, "Cycling"),
                    .init(22, "Metro train"),
                ],
                span: 0...30
            )
        ),

        ReadingDescriptor(
            id: .course,
            name: "Course",
            group: .location,
            symbol: "arrow.triangle.turn.up.right.diamond",
            source: "Core Location",
            channels: [ReadingChannel("Course", .angle)],
            permission: .locationWhenInUse,
            tile: .channel(0),
            explainer: Explainer(
                what: "The direction you are actually travelling in, in degrees from north. It is not the same as heading: you can walk north while holding the phone pointing east.",
                precision: "Only meaningful while you are moving; standing still, there is no course to report. It comes from successive satellite fixes, so it lags a sudden change of direction.",
                tryThis: "Walk in a square and watch the course step round in roughly 90° jumps."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(0, "North"),
                    .init(90, "East"),
                    .init(180, "South"),
                    .init(270, "West"),
                ],
                span: 0...360
            )
        ),

        ReadingDescriptor(
            id: .locationAccuracy,
            name: "Accuracy",
            group: .location,
            symbol: "scope",
            source: "Core Location",
            channels: [
                ReadingChannel("Horizontal", .length),
                ReadingChannel("Vertical", .length),
            ],
            permission: .locationWhenInUse,
            tile: .channel(0),
            explainer: Explainer(
                what: "How wrong your position might be. A horizontal accuracy of 5 metres means the phone believes you are somewhere within 5 metres of the coordinates it reported.",
                precision: "This is the phone's own estimate of its error, so treat it as a guide. Smaller is better; a sudden jump usually means you have lost sight of the sky.",
                tryThis: "Watch it as you walk out of a building — it often drops from tens of metres to under ten within a few seconds."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(5, "Clear sky"),
                    .init(20, "Built-up street"),
                    .init(65, "Indoors"),
                ],
                span: 0...100
            )
        ),

        // MARK: Device & activity

        ReadingDescriptor(
            id: .activity,
            name: "Steps today",
            group: .device,
            symbol: "figure.walk",
            source: "Core Motion, pedometer",
            channels: [
                ReadingChannel("Steps", .count(symbol: "steps")),
                ReadingChannel("Distance", .distance),
                ReadingChannel("Floors", .count(symbol: "floors")),
            ],
            permission: .motionFitness,
            tile: .channel(0),
            explainer: Explainer(
                what: "Steps, distance and floors climbed since midnight, counted by the phone's motion coprocessor whether or not Readout is open.",
                precision: "Step counts are usually within a few per cent over a walk. Distance is estimated from your stride, so it is rougher. Floors come from the barometer, and a lift counts too.",
                tryThis: "Compare the figure with the Health app — they come from the same place, so they should agree."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(2_000, "A short walk"),
                    .init(7_500, "An ordinary day"),
                    .init(10_000, "The usual target"),
                ],
                span: 0...15_000
            )
        ),

        ReadingDescriptor(
            id: .cadence,
            name: "Cadence & pace",
            group: .device,
            symbol: "metronome",
            source: "Core Motion, pedometer",
            channels: [
                ReadingChannel("Cadence", .cadence),
                ReadingChannel("Pace", .pace),
            ],
            permission: .motionFitness,
            tile: .channel(0),
            explainer: Explainer(
                what: "How often your feet are hitting the ground, and how long it would take you to cover a kilometre at this rate. Both are live, and both need you to be moving.",
                precision: "Averaged over the last few seconds, so it takes a moment to catch up when you speed up or stop. It reports nothing while you stand still.",
                tryThis: "Walk normally, then deliberately take smaller, quicker steps — cadence climbs while pace barely changes."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(100, "Strolling"),
                    .init(120, "Walking briskly"),
                    .init(160, "Running"),
                    .init(180, "Running fast"),
                ],
                span: 0...200
            )
        ),

        ReadingDescriptor(
            id: .proximity,
            name: "Proximity",
            group: .device,
            symbol: "sensor.tag.radiowaves.forward",
            source: "UIKit, proximity sensor",
            channels: [ReadingChannel("State", .none)],
            kind: .discrete,
            activation: .onDemand,
            tile: .state,
            explainer: Explainer(
                what: "The infrared sensor by the earpiece that notices when the phone is against your face, so iOS can switch the screen off during a call.",
                precision: "Near or far, nothing in between — iOS does not expose a distance. Running it blanks the screen when something covers the sensor, so Readout only turns it on while you are testing it.",
                tryThis: "Start the test and move your palm towards the top of the screen; it usually flips to Near at about 5 centimetres."
            )
        ),

        ReadingDescriptor(
            id: .battery,
            name: "Battery",
            group: .device,
            symbol: "battery.75percent",
            source: "UIKit, battery monitoring",
            channels: [ReadingChannel("Charge", .percentage)],
            tile: .channel(0),
            explainer: Explainer(
                what: "How much charge is left, and whether the phone is plugged in. It is not a sensor reading as such — iOS reports it from the battery's own management chip.",
                precision: "Reported in steps of about 5%, which is why it can appear to sit still for a while and then jump.",
                tryThis: "Plug the phone in and watch the state change to charging within a second or two."
            ),
            comparisons: ComparisonScale(
                references: [
                    .init(20, "Low Power Mode prompt"),
                    .init(80, "Optimised charging pause"),
                    .init(100, "Full"),
                ],
                span: 0...100
            )
        ),

        ReadingDescriptor(
            id: .thermalState,
            name: "Phone heat",
            group: .device,
            symbol: "thermometer.medium",
            source: "ProcessInfo",
            channels: [ReadingChannel("State", .none)],
            kind: .discrete,
            tile: .state,
            explainer: Explainer(
                what: "How hot the phone itself is running, in four steps: nominal, fair, serious and critical. iOS throttles performance as it climbs.",
                precision: "This is about the phone, not the room. iPhones do not let apps read air temperature at all, so Readout has no thermometer to offer — and would rather say so than make a number up.",
                tryThis: "Run a demanding game or charge in sunlight for a few minutes and watch it leave nominal."
            )
        ),
    ]

    private static let index: [ReadingID: ReadingDescriptor] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func descriptor(_ id: ReadingID) -> ReadingDescriptor {
        guard let descriptor = index[id] else {
            preconditionFailure("ReadingCatalog is missing a descriptor for \(id.rawValue)")
        }
        return descriptor
    }

    static func readings(in group: ReadingGroup) -> [ReadingDescriptor] {
        all.filter { $0.group == group }
    }
}
