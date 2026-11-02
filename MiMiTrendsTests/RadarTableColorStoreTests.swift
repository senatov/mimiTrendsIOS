import SwiftUI
import XCTest
@testable import MiMiTrends

@MainActor
final class RadarTableColorStoreTests: XCTestCase {
    func testOverridePersistsAndResetRestoresAppearanceDefaults() throws {
        let suite = "radar-table-colors-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = RadarTableColorStore(defaults: defaults)
        XCTAssertEqual(RadarColorHex.hex(first.color(.grid, dark: false)),
                       RadarTableColorRole.grid.defaultHexLight)
        XCTAssertEqual(RadarColorHex.hex(first.color(.headerFill, dark: true)),
                       RadarTableColorRole.headerFill.defaultHexDark)

        first.set(try XCTUnwrap(RadarColorHex.color("A1B2C3")), for: .grid)
        XCTAssertTrue(first.isCustomized(.grid))
        let restored = RadarTableColorStore(defaults: defaults)
        XCTAssertEqual(RadarColorHex.hex(restored.color(.grid, dark: false)), "A1B2C3")
        XCTAssertEqual(RadarColorHex.hex(restored.color(.grid, dark: true)), "A1B2C3")

        restored.reset(.grid)
        XCTAssertFalse(restored.isCustomized(.grid))
        XCTAssertNil(defaults.string(forKey: RadarTableColorRole.grid.key))
        XCTAssertEqual(RadarColorHex.hex(restored.color(.grid, dark: false)),
                       RadarTableColorRole.grid.defaultHexLight)
    }

    func testInvalidStoredColorFallsBackToDefault() throws {
        let suite = "radar-table-colors-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("not-a-color", forKey: RadarTableColorRole.headerText.key)
        let colors = RadarTableColorStore(defaults: defaults)
        XCTAssertFalse(colors.isCustomized(.headerText))
        XCTAssertEqual(RadarColorHex.hex(colors.color(.headerText, dark: false)),
                       RadarTableColorRole.headerText.defaultHexLight)
    }
}
