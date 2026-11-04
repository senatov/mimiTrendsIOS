import XCTest
@testable import MiMiTrends

final class RadarSearchKeywordTests: XCTestCase {
    func testDomainSuffixIsExcludedFromSearchKeyword() {
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Amazon.com, Inc.", symbol: "AMZN"), "Amazon")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Example com", symbol: "EXM"), "Example")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Booking.com Holdings, Inc.", symbol: "BKNG"), "Booking Holdings")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Comcast Corporation", symbol: "CMCSA"), "Comcast")
    }
}
