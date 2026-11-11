import XCTest
@testable import MiMiTrends

final class RecentCoverageClientTests: XCTestCase {
    func testNewsKeepsOlderAndUndatedItemsAndSortsNewestFirst() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let items = [
            item("older", date: now.addingTimeInterval(-11 * 3_600)),
            item("unknown", date: nil),
            item("current", date: now.addingTimeInterval(-3_600)),
            item("recent", date: now.addingTimeInterval(-9 * 3_600)),
            item("future", date: now.addingTimeInterval(60)),
            item("current", date: now.addingTimeInterval(-2 * 3_600))
        ]
        XCTAssertEqual(RecentCoverageClient.displayItems(items).map(\.title),
                       ["future", "current", "recent", "older", "unknown"])
    }

    func testTickerFeedKeepsNewsLinkAndPublisher() throws {
        let xml = """
        <rss><channel><item><title>Cipher opens new data center</title>
        <link>https://finance.yahoo.com/news/cipher-opens-center-123.html</link>
        <source>Example Wire</source><pubDate>Wed, 11 Nov 2026 18:00:00 GMT</pubDate>
        </item></channel></rss>
        """
        let items = try RecentCoverageClient.yahooFeedItems(Data(xml.utf8))
        XCTAssertEqual(items.map(\.publisher), ["Example Wire"])
        XCTAssertEqual(items.first?.url.absoluteString,
                       "https://finance.yahoo.com/news/cipher-opens-center-123.html")
        XCTAssertNotNil(items.first?.publishedAt)
    }

    func testYahooSearchKeepsEveryNewsItemAndItsPublisher() throws {
        let json = """
        {"news":[
          {"title":"Cipher report","publisher":"Business Wire","link":"https://finance.yahoo.com/news/cipher-report.html","providerPublishTime":1794416176},
          {"title":"Cipher outlook","publisher":"Example News","link":"https://example.com/cipher-outlook","providerPublishTime":1794416000}
        ]}
        """
        let items = try RecentCoverageClient.yahooSearchItems(Data(json.utf8))
        XCTAssertEqual(items.map(\.title), ["Cipher report", "Cipher outlook"])
        XCTAssertEqual(items.map(\.publisher), ["Business Wire", "Example News"])
        XCTAssertEqual(RecentCoverageClient.displayItems(items).count, 2)
    }

    private func item(_ title: String, date: Date?) -> CoverageItem {
        CoverageItem(title: title, publisher: "Fixture",
                     url: URL(string: "https://example.com/\(title)")!,
                     publishedAt: date, publishedLabel: nil)
    }
}
