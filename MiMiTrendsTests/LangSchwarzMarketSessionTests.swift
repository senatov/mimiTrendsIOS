import XCTest
@testable import MiMiTrends

final class LangSchwarzMarketSessionTests: XCTestCase {
    func testUSAndEuropeanUnderlyingSessionsCanDiffer() throws {
        let duringUSSession = try date("2026-11-09T18:00:00+01:00")
        XCTAssertFalse(LangSchwarzMarketSession.isUnderlyingMarketOpen(
            for: .langSchwarzGermany, at: duringUSSession
        ))
        XCTAssertTrue(LangSchwarzMarketSession.isUnderlyingMarketOpen(
            for: .langSchwarzAmerica, at: duringUSSession
        ))
        XCTAssertTrue(LangSchwarzMarketSession.isQuoteVenueOpen(at: duringUSSession))
    }

    func testQuoteVenueClosesAfterItsExtendedWeekdaySession() throws {
        XCTAssertFalse(LangSchwarzMarketSession.isQuoteVenueOpen(
            at: try date("2026-11-09T23:30:00+01:00")
        ))
    }

    func testLangSchwarzWeekendQuoteSessionsAreRecognized() throws {
        XCTAssertTrue(LangSchwarzMarketSession.isQuoteVenueOpen(
            at: try date("2026-11-07T11:00:00+01:00")
        ))
        XCTAssertTrue(LangSchwarzMarketSession.isQuoteVenueOpen(
            at: try date("2026-11-08T18:00:00+01:00")
        ))
    }

    private func date(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        let date = try XCTUnwrap(formatter.date(from: value))
        return date
    }
}
