import Foundation
import XCTest
@testable import MiMiTrends

final class RadarScanPreferencesTests: XCTestCase {
    func testRapidDropDefaultsAreAvailableWithoutSavedPreferences() {
        let defaults = UserDefaults(suiteName: "RadarScanPreferencesTests.\(UUID().uuidString)")!
        let settings = RadarScanPreferencesStore.load(from: defaults)

        XCTAssertEqual(settings.crashPercent, 1.0)
        XCTAssertEqual(settings.sustainedCrashPercent, 1.5)
        XCTAssertEqual(settings.risePercent, 0.8)
        XCTAssertEqual(settings.sustainedMoveMinimumTurnover, 50_000_000)
    }

    func testLegacyRapidDropDefaultsMigrateAndKeepOtherPreferences() throws {
        let suite = "RadarScanPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var legacy = RadarScanPreferences()
        legacy.crashPercent = RadarScanThresholdDefaults.legacyShortDropPercent
        legacy.sustainedCrashPercent = RadarScanThresholdDefaults.legacySustainedDropPercent
        legacy.risePercent = 1.25
        defaults.set(try JSONEncoder().encode(legacy), forKey: RadarScanPreferencesStore.key)

        let restored = RadarScanPreferencesStore.load(from: defaults)

        XCTAssertEqual(restored.crashPercent, 1.0)
        XCTAssertEqual(restored.sustainedCrashPercent, 1.5)
        XCTAssertEqual(restored.risePercent, 1.25)
        XCTAssertEqual(RadarScanPreferencesStore.load(from: defaults), restored)
    }

    func testSettingsRoundTripAndBounds() throws {
        let suite = "RadarScanPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = RadarScanPreferences()
        settings.risePercent = 1.35
        settings.crashWindowMinutes = 999
        settings.minimumTurnover = .infinity

        try RadarScanPreferencesStore.save(settings, to: defaults)
        let restored = RadarScanPreferencesStore.load(from: defaults)

        XCTAssertEqual(restored.risePercent, 1.35)
        XCTAssertEqual(restored.crashWindowMinutes, 15)
        XCTAssertEqual(restored.minimumTurnover, 250_000)
    }
}
