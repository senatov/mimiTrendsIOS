import XCTest
@testable import MiMiTrends

final class RecentCoverageClientTests: XCTestCase {
    func testRecentNewsRequiresVerifiedTimeAndSortsNewestFirst() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            item("older", date: now.addingTimeInterval(-49 * 3_600)),
            item("unknown", date: nil),
            item("current", date: now.addingTimeInterval(-3_600)),
            item("recent", date: now.addingTimeInterval(-47 * 3_600)),
            item("future", date: now.addingTimeInterval(60)),
            item("current", date: now.addingTimeInterval(-2 * 3_600))
        ]
        XCTAssertEqual(RecentCoverageClient.recentItems(items, now: now).map(\.title),
                       ["current", "recent"])
    }

    func testXSearchUsesCashtagAndLatestView() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let url = try XCTUnwrap(XCashtagSearch.latestURL(symbol: "aapl", now: now))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "x.com")
        XCTAssertEqual(parts.queryItems?.first(where: { $0.name == "f" })?.value, "live")
        XCTAssertTrue(parts.queryItems?.first(where: { $0.name == "q" })?.value?.hasPrefix("$AAPL since:") == true)
        XCTAssertNil(XCashtagSearch.latestURL(symbol: "AAPL&bad"))
    }

    private func item(_ title: String, date: Date?) -> CoverageItem {
        CoverageItem(title: title, publisher: "Fixture",
                     url: URL(string: "https://example.com/\(title)")!,
                     publishedAt: date, publishedLabel: nil)
    }
}
