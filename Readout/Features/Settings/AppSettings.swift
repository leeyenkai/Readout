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

    var displayUnits: DisplayUnits {
        DisplayUnits(
            system: unitSystem.resolved(),
            acceleration: accelerationUnit,
            coordinates: coordinateFormat
        )
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
