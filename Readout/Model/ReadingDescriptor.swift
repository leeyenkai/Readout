import Foundation

/// Which iOS permission a reading needs, and the one line shown before asking (R-54).
enum SensorPermission: String, CaseIterable, Identifiable, Sendable {
    case motionFitness
    case locationWhenInUse
    case microphone
    case camera

    var id: String { rawValue }

    var title: String {
        switch self {
        case .motionFitness: "Motion & Fitness"
        case .locationWhenInUse: "Location"
        case .microphone: "Microphone"
        case .camera: "Camera"
        }
    }

    /// Shown on the card that precedes the system prompt.
    var why: String {
        switch self {
        case .motionFitness:
            "The barometer and step counter live behind Motion & Fitness access. Readout uses them for pressure, altitude change and your pace."
        case .locationWhenInUse:
            "Your location is needed for coordinates, speed, course and for pointing the compass at true north. It never leaves the phone."
        case .microphone:
            "Readout reads the microphone's level to show how loud it is. No audio is recorded or saved."
        case .camera:
            "Readout reads the camera's exposure settings to estimate brightness. No photo is taken, shown or saved."
        }
    }

    var symbol: String {
        switch self {
        case .motionFitness: "figure.walk.motion"
        case .locationWhenInUse: "location.circle"
        case .microphone: "mic.circle"
        case .camera: "camera.circle"
        }
    }
}

/// Whether a reading may run as soon as it is on screen.
enum ReadingActivation: Sendable {
    /// Starts when a view showing it appears (R-18).
    case whileVisible
    /// Needs a deliberate tap, because the sensor is intrusive: camera, microphone,
    /// proximity (which blanks the screen) (R-19, R-68).
    case onDemand
}

/// How a reading's value is shaped.
enum ReadingKind: Sendable {
    case continuous
    case discrete
    case coordinates
}

/// What a tile shows as its single live value (R-17).
enum TileSummary: Sendable {
    case channel(Int)
    case magnitude(label: String)
    case state
    case coordinates
}

/// How a recording's chosen rate applies to a reading (R-39).
enum RecordingCadence: Sendable {
    /// The provider follows the requested `ActivationRate`, so High really means 50 Hz:
    /// the four Core Motion readings.
    case driven
    /// The provider has a rate of its own — the microphone's level meter, the camera, the
    /// device readings — but a recording still keeps no more than the chosen rate asks for.
    case capped
    /// The framework decides when a value arrives and every one is kept: location, air
    /// pressure and the pedometer, which R-39 exempts from the chosen rate.
    case free
}

/// One channel of a reading, for example the x axis of acceleration.
struct ReadingChannel: Sendable, Hashable, Identifiable {
    let name: String
    let unit: ValueUnit
    let axis: Axis?

    var id: String { name }

    init(_ name: String, _ unit: ValueUnit, axis: Axis? = nil) {
        self.name = name
        self.unit = unit
        self.axis = axis
    }
}

/// The plain-English card under the chart (R-28).
struct Explainer: Sendable, Equatable {
    /// What the sensor is and what it measures.
    let what: String
    /// How precise it is, and where it comes from.
    let precision: String
    /// One thing to go and try.
    let tryThis: String
}

/// Everything the UI needs to know about a reading. Adding a reading means adding one of
/// these and a provider — never a new view.
struct ReadingDescriptor: Sendable, Identifiable {
    let id: ReadingID
    let name: String
    let group: ReadingGroup
    let symbol: String
    /// Shown verbatim under the value, so every number says where it came from (P-2).
    let source: String
    let channels: [ReadingChannel]
    let kind: ReadingKind
    let activation: ReadingActivation
    let permission: SensorPermission?
    let tile: TileSummary
    let explainer: Explainer
    let comparisons: ComparisonScale?
    /// Set when the figure is an estimate rather than a sensor reading (R-10, R-66).
    let estimateNote: String?
    /// Whether a recording can drive this reading faster than its default rate (R-39).
    let recordingCadence: RecordingCadence
    /// The stem of this reading's CSV column names and file name. Defaults to the
    /// identifier in snake case; set where a shorter name reads better, as SPEC §8.4's
    /// `accel_x_g` does.
    let csvPrefix: String

    init(
        id: ReadingID,
        name: String,
        group: ReadingGroup,
        symbol: String,
        source: String,
        channels: [ReadingChannel],
        kind: ReadingKind = .continuous,
        activation: ReadingActivation = .whileVisible,
        permission: SensorPermission? = nil,
        tile: TileSummary = .channel(0),
        explainer: Explainer,
        comparisons: ComparisonScale? = nil,
        estimateNote: String? = nil,
        recordingCadence: RecordingCadence = .capped,
        csvPrefix: String? = nil
    ) {
        self.id = id
        self.name = name
        self.group = group
        self.symbol = symbol
        self.source = source
        self.channels = channels
        self.kind = kind
        self.activation = activation
        self.permission = permission
        self.tile = tile
        self.explainer = explainer
        self.comparisons = comparisons
        self.estimateNote = estimateNote
        self.recordingCadence = recordingCadence
        self.csvPrefix = csvPrefix ?? Self.snakeCased(id.rawValue)
    }

    /// `relativeAltitude` becomes `relative_altitude` and a channel called "X" becomes `x`,
    /// so a column name reads the way a CSV reader expects (R-45).
    static func snakeCased(_ text: String) -> String {
        var result = ""
        for (index, character) in text.enumerated() {
            if character.isUppercase {
                if index > 0 { result.append("_") }
                result.append(character.lowercased())
            } else if character.isLetter || character.isNumber {
                result.append(character)
            } else {
                result.append("_")
            }
        }
        return result
    }

    var isMultiAxis: Bool { channels.count > 1 && channels.allSatisfy { $0.axis != nil } }

    var isChartable: Bool { kind == .continuous }

    /// The one value a tile shows, per `tile` (R-17).
    func summaryValue(_ sample: SensorSample) -> Double? {
        switch tile {
        case .channel(let index): sample.value(index)
        case .magnitude: sample.magnitude
        case .state, .coordinates: nil
        }
    }

    /// Proximity blanks the screen while monitoring, so its detail view puts it behind a
    /// button rather than starting on appear (R-68).
    var requiresExplicitStart: Bool { id == .proximity }

    /// The unit used for the tile's single value.
    var summaryUnit: ValueUnit {
        switch tile {
        case .channel(let index): channels.indices.contains(index) ? channels[index].unit : .none
        case .magnitude: channels.first?.unit ?? .none
        case .state, .coordinates: .none
        }
    }
}
