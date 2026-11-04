import XCTest
@testable import MiMiTrends

final class RecentCoverageClientTests: XCTestCase {
    func testRecentNewsRequiresVerifiedTimeAndSortsNewestFirst() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            item("older", date: now.addingTimeInterval(-11 * 3_600)),
            item("unknown", date: nil),
            item("current", date: now.addingTimeInterval(-3_600)),
            item("recent", date: now.addingTimeInterval(-9 * 3_600)),
            item("future", date: now.addingTimeInterval(60)),
            item("current", date: now.addingTimeInterval(-2 * 3_600))
        ]
        XCTAssertEqual(RecentCoverageClient.recentItems(items, now: now).map(\.title),
                       ["current", "recent"])
    }

    func testReutersSearchUsesTickerAsQuery() throws {
        let url = try XCTUnwrap(ReutersSearch.url(symbol: " aapl "))
        let parts = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(parts.host, "www.reuters.com")
        XCTAssertEqual(parts.path, "/site-search/")
        XCTAssertEqual(parts.queryItems, [URLQueryItem(name: "query", value: "AAPL")])
        XCTAssertEqual(ReutersSearch.url(symbol: "IFX.DE")?.query, "query=IFX.DE")
        XCTAssertNil(ReutersSearch.url(symbol: "AAPL&bad"))
    }

    func testReutersStoryCardsBecomeDatedNewsAndOldResultsAreDiscarded() throws {
        let html = """
        <ul data-testid="ListContainer">
          <li data-testid="StoryCard">
            <time data-testid="DateLineText" datetime="2026-11-04T14:30:00.000Z">November 4</time>
            <a data-testid="TitleLink" href="/business/amd-new-chips/"><span data-testid="TitleHeading">AMD &amp; partners announce chips</span></a>
          </li>
          <li data-testid="StoryCard">
            <time data-testid="DateLineText" datetime="2026-02-04T15:41:30.780Z">February 4</time>
            <a data-testid="TitleLink" href="/business/older-amd-story/"><span data-testid="TitleHeading">Older AMD story</span></a>
          </li>
        </ul>
        """
        let items = ReutersSearchParser.parse(Data(html.utf8))
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].title, "AMD & partners announce chips")
        XCTAssertEqual(items[0].url.absoluteString, "https://www.reuters.com/business/amd-new-chips/")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-04T16:00:00Z"))
        XCTAssertEqual(RecentCoverageClient.recentItems(items, now: now).map(\.title),
                       ["AMD & partners announce chips"])
    }

    private func item(_ title: String, date: Date?) -> CoverageItem {
        CoverageItem(title: title, publisher: "Fixture",
                     url: URL(string: "https://example.com/\(title)")!,
                     publishedAt: date, publishedLabel: nil)
    }
}
