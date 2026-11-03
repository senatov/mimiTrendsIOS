import XCTest
@testable import MiMiTrends

final class FMPHistoricalPriceSourceTests: XCTestCase {
    func testDailyBarsDecodeAndSort() throws {
        let payload = """
        [
          {"symbol":"AAPL","date":"2026-11-02","open":295,"high":299,"low":294,"close":298,"volume":1000},
          {"symbol":"AAPL","date":"2026-10-30","open":290,"high":294,"low":289,"close":293,"volume":900}
        ]
        """
        let bars = try FMPHistoricalPriceSource.decode(Data(payload.utf8), symbol: "AAPL")
        XCTAssertEqual(bars.count, 2)
        XCTAssertEqual(bars.map(\.close), [293, 298])
        XCTAssertEqual(bars[0].minuteEpochSeconds % 86_400, 12 * 3_600)
        XCTAssertEqual(bars[1].volumeStatus, .reported)
        XCTAssertTrue(bars.allSatisfy(\.isValid))
    }

    func testInvalidOrDifferentSymbolIsRejected() {
        let payload = """
        [{"symbol":"MSFT","date":"2026-11-02","open":1,"high":2,"low":1,"close":2,"volume":10}]
        """
        XCTAssertThrowsError(try FMPHistoricalPriceSource.decode(Data(payload.utf8), symbol: "AAPL"))
    }

    func testYearAndWeekRangesUseDailyBars() {
        XCTAssertTrue(RadarChartRange.oneWeek.usesDailyBars)
        XCTAssertTrue(RadarChartRange.oneYear.usesDailyBars)
        XCTAssertEqual(RadarChartRange.oneWeek.seconds, 7 * 86_400)
        XCTAssertEqual(RadarChartRange.oneYear.seconds, 365 * 86_400)
    }
}
