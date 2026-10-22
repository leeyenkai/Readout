import Foundation
import Observation

/// Everything the user can change, persisted on the device (R-8, R-22, R-23).
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        unitSystem = defaults.decoded(UnitSystem.self, forKey: Key.unitSystem) ?? .automatic
        accelerationUnit = defaults.decoded(AccelerationUnit.self, forKey: Key.accelerationUnit) ?? .gravity
        coordinateFormat = defaults.decoded(CoordinateFormat.self, forKey: Key.coordinateFormat) ?? .decimal
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        usesTrueNorth = defaults.object(forKey: Key.trueNorth) as? Bool ?? true
        accelerationIncludesGravity = defaults.object(forKey: Key.gravity) as? Bool ?? false
        soundRespondsFast = defaults.object(forKey: Key.soundFast) as? Bool ?? true
        soundCalibrationOffset = defaults.object(forKey: Key.soundOffset) as? Double ?? 0
        lightCalibration = defaults.object(forKey: Key.lightCalibration) as? Double ?? 1
        hiddenReadings = Set(
            (defaults.array(forKey: Key.hiddenReadings) as? [String] ?? []).compactMap(ReadingID.init(rawValue:))
        )
        readingOrder = (defaults.array(forKey: Key.readingOrder) as? [String] ?? [])
            .compactMap(ReadingID.init(rawValue:))
        hasSeenWelcome = defaults.object(forKey: Key.hasSeenWelcome) as? Bool ?? false
        themeIdentifier = defaults.decoded(ThemeID.self, forKey: Key.theme) ?? ThemeID.default
        interfaceScale = (defaults.object(forKey: Key.interfaceScale) as? Int)
            .flatMap(InterfaceScale.init(rawValue:)) ?? .default
        recordingLimit = defaults.decoded(RecordingLimit.self, forKey: Key.recordingLimit) ?? .default
        usesAppleMaps = defaults.object(forKey: Key.usesAppleMaps) as? Bool ?? false
        levelZero = defaults.data(forKey: Key.levelZero)
            .flatMap { try? JSONDecoder().decode(LevelZero.self, from: $0) } ?? .none
        attitudeShowsAxes = defaults.object(forKey: Key.attitudeShowsAxes) as? Bool ?? true
        attitudeSways = defaults.object(forKey: Key.attitudeSways) as? Bool ?? true
    }

    var unitSystem: UnitSystem { didSet { defaults.encode(unitSystem, forKey: Key.unitSystem) } }
    var accelerationUnit: AccelerationUnit { didSet { defaults.encode(accelerationUnit, forKey: Key.accelerationUnit) } }
    var coordinateFormat: CoordinateFormat { didSet { defaults.encode(coordinateFormat, forKey: Key.coordinateFormat) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    var usesTrueNorth: Bool { didSet { defaults.set(usesTrueNorth, forKey: Key.trueNorth) } }
    var accelerationIncludesGravity: Bool { didSet { defaults.set(accelerationIncludesGravity, forKey: Key.gravity) } }
    var soundRespondsFast: Bool { didSet { defaults.set(soundRespondsFast, forKey: Key.soundFast) } }

    /// Added to every sound reading, in dB (R-66).
    var soundCalibrationOffset: Double { didSet { defaults.set(soundCalibrationOffset, forKey: Key.soundOffset) } }
    /// Multiplier on the lux estimate (R-10).
    var lightCalibration: Double { didSet { defaults.set(lightCalibration, forKey: Key.lightCalibration) } }

    /// Tiles the user has hidden from the grid (R-22).
    var hiddenReadings: Set<ReadingID> {
        didSet { defaults.set(hiddenReadings.map(\.rawValue), forKey: Key.hiddenReadings) }
    }

    /// The order the user has dragged the tiles into. Readings missing from it — a new one
    /// added by an update, or an order never changed — follow in catalog order (R-22).
    var readingOrder: [ReadingID] {
        didSet { defaults.set(readingOrder.map(\.rawValue), forKey: Key.readingOrder) }
    }

    /// Set once the first-run explainer has been dismissed (R-73).
    var hasSeenWelcome: Bool {
        didSet { defaults.set(hasSeenWelcome, forKey: Key.hasSeenWelcome) }
    }

    /// The chosen look (R-77). Stored as the identifier; `theme` resolves it, so a raw value
    /// this version does not know falls back to the default instead of failing. Nothing is
    /// stored until the user picks one, so somebody who chose System keeps it.
    var themeIdentifier: ThemeID {
        didSet { defaults.encode(themeIdentifier, forKey: Key.theme) }
    }

    var theme: AppTheme { ThemeCatalog.theme(themeIdentifier) }

    /// How large the interface is drawn, on top of the phone's own text size (R-78).
    var interfaceScale: InterfaceScale {
        didSet { defaults.set(interfaceScale.rawValue, forKey: Key.interfaceScale) }
    }

    /// How long a recording may run before it stops itself (Q-4, R-80).
    var recordingLimit: RecordingLimit {
        didSet { defaults.encode(recordingLimit, forKey: Key.recordingLimit) }
    }

    /// Whether a recorded route may be shown on Apple Maps (R-76).
    ///
    /// Off until the user says otherwise, and the only setting in Readout that lets anything
    /// reach the network: Apple Maps fetches its own tiles. With it off, the route is plotted
    /// from the session's own fixes and the app still makes no request at all (R-59).
    var usesAppleMaps: Bool {
        didSet { defaults.set(usesAppleMaps, forKey: Key.usesAppleMaps) }
    }

    /// What Zero has taken off the spirit level, per mode, kept between visits: a zero is a
    /// correction for this phone and its case, not for one look at the tool (R-32).
    var levelZero: LevelZero {
        didSet { defaults.set(try? JSONEncoder().encode(levelZero), forKey: Key.levelZero) }
    }

    /// Whether the 3D phone shows its three axes (R-86).
    var attitudeShowsAxes: Bool {
        didSet { defaults.set(attitudeShowsAxes, forKey: Key.attitudeShowsAxes) }
    }

    /// Whether the 3D phone sways with the pushes it is given (R-86).
    var attitudeSways: Bool {
        didSet { defaults.set(attitudeSways, forKey: Key.attitudeSways) }
    }

    /// Whether anything on the Appearance screen has been changed, so it can offer to undo it.
    var hasAppearanceChanges: Bool {
        themeIdentifier != ThemeID.default || interfaceScale != .default
    }

    func resetAppearance() {
        themeIdentifier = ThemeID.default
        interfaceScale = .default
    }

    var displayUnits: DisplayUnits {
        DisplayUnits(
            system: unitSystem.resolved(),
            acceleration: accelerationUnit,
            coordinates: coordinateFormat
        )
    }

    /// Whether the user has corrected either estimate, so Settings can offer to clear it.
    var hasCalibration: Bool {
        soundCalibrationOffset != 0 || lightCalibration != 1
    }

    func resetCalibration() {
        soundCalibrationOffset = 0
        lightCalibration = 1
    }

    func isHidden(_ reading: ReadingID) -> Bool {
        hiddenReadings.contains(reading)
    }

    func setHidden(_ hidden: Bool, for reading: ReadingID) {
        if hidden {
            hiddenReadings.insert(reading)
        } else {
            hiddenReadings.remove(reading)
        }
    }

    func showAllReadings() {
        hiddenReadings = []
    }

    /// Catalog order, with the user's own arrangement applied where they have made one.
    func ordered(_ readings: [ReadingDescriptor]) -> [ReadingDescriptor] {
        guard !readingOrder.isEmpty else { return readings }
        let rank = Dictionary(uniqueKeysWithValues: readingOrder.enumerated().map { ($1, $0) })
        return readings.enumerated().sorted { left, right in
            // A reading the order has never seen keeps its catalog position, after the ones
            // that have been arranged.
            let leftRank = rank[left.element.id] ?? readingOrder.count + left.offset
            let rightRank = rank[right.element.id] ?? readingOrder.count + right.offset
            return leftRank < rightRank
        }.map(\.element)
    }

    /// Moves one reading to sit where another one is, and remembers the result (R-22).
    func move(_ reading: ReadingID, before target: ReadingID) {
        guard reading != target else { return }
        var order = readingOrder.isEmpty ? ReadingCatalog.all.map(\.id) : readingOrder
        for missing in ReadingCatalog.all.map(\.id) where !order.contains(missing) {
            order.append(missing)
        }
        guard let from = order.firstIndex(of: reading) else { return }
        order.remove(at: from)
        guard let to = order.firstIndex(of: target) else { return }
        order.insert(reading, at: to)
        readingOrder = order
    }

    func resetOrder() {
        readingOrder = []
    }

    private enum Key {
        static let unitSystem = "settings.unitSystem"
        static let accelerationUnit = "settings.accelerationUnit"
        static let coordinateFormat = "settings.coordinateFormat"
        static let haptics = "settings.haptics"
        static let trueNorth = "settings.trueNorth"
        static let gravity = "settings.accelerationIncludesGravity"
        static let soundFast = "settings.soundRespondsFast"
        static let soundOffset = "settings.soundCalibrationOffset"
        static let lightCalibration = "settings.lightCalibration"
        static let hiddenReadings = "settings.hiddenReadings"
        static let readingOrder = "settings.readingOrder"
        static let hasSeenWelcome = "settings.hasSeenWelcome"
        static let theme = "settings.theme"
        static let interfaceScale = "settings.interfaceScale"
        static let recordingLimit = "settings.recordingLimit"
        static let usesAppleMaps = "settings.usesAppleMaps"
        static let levelZero = "settings.levelZero"
        static let attitudeShowsAxes = "settings.attitudeShowsAxes"
        static let attitudeSways = "settings.attitudeSways"
    }
}

private extension UserDefaults {
    func decoded<T: RawRepresentable>(_ type: T.Type, forKey key: String) -> T? where T.RawValue == String {
        guard let raw = string(forKey: key) else { return nil }
        return T(rawValue: raw)
    }

    func encode<T: RawRepresentable>(_ value: T, forKey key: String) where T.RawValue == String {
        set(value.rawValue, forKey: key)
    }
}
