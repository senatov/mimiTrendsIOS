import XCTest
@testable import MiMiTrends

final class ControlAppearanceTests: XCTestCase {
    func testAutomaticTextContrastsWithSavedButtonBackground() throws {
        let lightBackground = try XCTUnwrap(ControlAppearance.contrastingTextColor(for: "FFFFFF"))
        let darkBackground = try XCTUnwrap(ControlAppearance.contrastingTextColor(for: "172B48"))
        XCTAssertEqual(RadarColorHex.hex(lightBackground), "000000")
        XCTAssertEqual(RadarColorHex.hex(darkBackground), "FFFFFF")
        XCTAssertNil(ControlAppearance.contrastingTextColor(for: "invalid"))
    }
}
