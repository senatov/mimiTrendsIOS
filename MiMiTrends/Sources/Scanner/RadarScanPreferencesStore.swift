import Foundation

enum RadarScanPreferencesStore {
    static let key = "radar.scanPreferences.v1"
    private static let dropThresholdMigrationKey = "radar.scanPreferences.rapidDropDefaultsMigrated.v1"

    static func load(from defaults: UserDefaults = .standard) -> RadarScanPreferences {
        guard let data = defaults.data(forKey: key),
              var value = try? JSONDecoder().decode(RadarScanPreferences.self, from: data) else {
            return RadarScanPreferences()
        }
        value = value.validated
        guard !defaults.bool(forKey: dropThresholdMigrationKey) else { return value }
        if value.crashPercent == RadarScanThresholdDefaults.legacyShortDropPercent,
           value.crashWindowMinutes == 5 {
            value.crashPercent = RadarScanThresholdDefaults.shortDropPercent
        }
        if value.sustainedCrashPercent == RadarScanThresholdDefaults.legacySustainedDropPercent,
           value.sustainedCrashWindowMinutes == 15 {
            value.sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
        }
        defaults.set(true, forKey: dropThresholdMigrationKey)
        try? save(value, to: defaults)
        return value
    }

    static func save(_ value: RadarScanPreferences, to defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(value.validated), forKey: key)
        defaults.set(true, forKey: dropThresholdMigrationKey)
    }
}
