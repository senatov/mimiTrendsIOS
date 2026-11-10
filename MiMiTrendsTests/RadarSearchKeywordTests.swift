import XCTest
@testable import MiMiTrends

final class RadarSearchKeywordTests: XCTestCase {
    func testDomainSuffixIsExcludedFromSearchKeyword() {
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Amazon.com, Inc.", symbol: "AMZN"), "Amazon")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Example com", symbol: "EXM"), "Example")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Booking.com Holdings, Inc.", symbol: "BKNG"), "Booking Holdings")
        XCTAssertEqual(RadarSearchKeyword.from(companyName: "Comcast Corporation", symbol: "CMCSA"), "Comcast")
    }

    func testUppercaseNamesLoseDenominationAndStayWithinTwoWords() {
        XCTAssertEqual(RadarSearchKeyword.cleanedCompanyName("NVIDIA CORP. DL-,001", symbol: "LS:43763"), "Nvidia")
        XCTAssertEqual(RadarSearchKeyword.cleanedCompanyName("DOW INC DL- 01", symbol: "DOW"), "DOW")
        XCTAssertEqual(RadarSearchKeyword.cleanedCompanyName("DELL TECHS INC C DL-,01", symbol: "DELL"), "Dell Techs")
    }

    func testLongHyphenatedCompanyNameUsesFirstWordAsSearchKeyword() {
        XCTAssertEqual(
            RadarSearchKeyword.from(
                companyName: "Münchener Rückversicherungs-Gesellschaft AG in München",
                symbol: "MUV2.DE"
            ),
            "Münchener"
        )
    }
}
