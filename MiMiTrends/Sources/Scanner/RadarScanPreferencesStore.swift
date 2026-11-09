import Foundation

enum RadarScanPreferencesStore {
    static let key = "radar.scanPreferences.v1"
    private static let dropThresholdMigrationKey = "radar.scanPreferences.rapidDropDefaultsMigrated.v1"
    private static let movementProfileMigrationKey = "radar.scanPreferences.movementProfileMigrated.v1"
    private static let quickMovesMigrationKey = "radar.scanPreferences.quickMovesMigrated.v1"

    private static let previousShortDropPercent = 1.0
    private static let previousSustainedDropPercent = 1.5
    private static let previousRisePercent = 0.8
    private static let previousSustainedMovePercent = 0.8
    private static let previousSustainedMoveWindowMinutes = 180

    static func load(from defaults: UserDefaults = .standard) -> RadarScanPreferences {
        guard let data = defaults.data(forKey: key),
              var value = try? JSONDecoder().decode(RadarScanPreferences.self, from: data) else {
            return RadarScanPreferences()
        }
        value = value.validated
        var changed = false

        if !defaults.bool(forKey: dropThresholdMigrationKey) {
            if value.crashPercent == RadarScanThresholdDefaults.legacyShortDropPercent,
               value.crashWindowMinutes == 5 {
                value.crashPercent = RadarScanThresholdDefaults.shortDropPercent
            }
            if value.sustainedCrashPercent == RadarScanThresholdDefaults.legacySustainedDropPercent,
               value.sustainedCrashWindowMinutes == 15 {
                value.sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
            }
            defaults.set(true, forKey: dropThresholdMigrationKey)
            changed = true
        }

        if !defaults.bool(forKey: movementProfileMigrationKey) {
            if value.crashPercent == previousShortDropPercent && value.crashWindowMinutes == 5 {
                value.crashPercent = RadarScanThresholdDefaults.shortDropPercent
            }
            if value.sustainedCrashPercent == previousSustainedDropPercent && value.sustainedCrashWindowMinutes == 15 {
                value.sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
            }
            if value.risePercent == previousRisePercent && value.riseWindowMinutes == 5 {
                value.risePercent = RadarScanThresholdDefaults.sharpReboundPercent
            }
            if value.sustainedMovePercent == previousSustainedMovePercent &&
                value.sustainedMoveWindowMinutes == previousSustainedMoveWindowMinutes {
                value.sustainedMovePercent = RadarScanThresholdDefaults.smoothRisePercent
                value.sustainedMoveWindowMinutes = RadarScanThresholdDefaults.smoothRiseWindowMinutes
            }
            defaults.set(true, forKey: movementProfileMigrationKey)
            changed = true
        }

        if !defaults.bool(forKey: quickMovesMigrationKey) {
            if value.crashPercent == 2.0 && value.crashWindowMinutes == 5 {
                value.crashPercent = RadarScanThresholdDefaults.shortDropPercent
            }
            if value.sustainedCrashPercent == 3.5 && value.sustainedCrashWindowMinutes == 15 {
                value.sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
            }
            if value.risePercent == 1.2 && value.riseWindowMinutes == 5 {
                value.risePercent = RadarScanThresholdDefaults.sharpReboundPercent
            }
            defaults.set(true, forKey: quickMovesMigrationKey)
            changed = true
        }

        if changed { try? save(value, to: defaults) }
        return value
    }

    static func save(_ value: RadarScanPreferences, to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(value.validated), forKey: key)
        defaults.set(true, forKey: dropThresholdMigrationKey)
        defaults.set(true, forKey: quickMovesMigrationKey)
    }
}
