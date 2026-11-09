import Foundation
import XCTest
@testable import MiMiTrends

final class MarketPageQuoteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_617_200) // 2026-11-02 12:00 Berlin

    func testLangSchwarzConvertsUSDAndRejectsStaleRows() throws {
        let fresh = row(wkn: "A0WMPJ", item: "41849", bid: "33,5500&nbsp;€",
                        ask: "33,6000&nbsp;€", time: "11:59:30")
        let dollars = row(wkn: "A0WMPK", item: "41850", bid: "33,5500&nbsp;$",
                          ask: "33,6000&nbsp;$", time: "11:59:30")
        let stale = row(wkn: "A0WMPL", item: "41851", bid: "33,5500&nbsp;€",
                        ask: "33,6000&nbsp;€", time: "11:20:00")
        let html = "<table>" + Array(repeating: fresh, count: 10).joined() + dollars + stale + "</table>"
        let quotes = try LangSchwarzQuoteSource.decode(html, now: now,
                                                        euroUSD: (1.12, Int64(now.timeIntervalSince1970 * 1_000)))
        XCTAssertEqual(quotes.count, 2)
        XCTAssertEqual(quotes.first(where: { $0.identifier == "41849" })?.midpointEUR, 33.575)
        XCTAssertEqual(quotes.first(where: { $0.identifier == "41850" })?.midpointEUR ?? 0,
                       33.575 / 1.12, accuracy: 0.0001)
    }

    func testLangSchwarzStaleQuotesAreClassifiedAsNoFreshQuotes() {
        let stale = row(wkn: "A0WMPL", item: "41851", bid: "33,5500&nbsp;€",
                        ask: "33,6000&nbsp;€", time: "11:20:00")
        let html = "<table>" + Array(repeating: stale, count: 10).joined() + "</table>"
        XCTAssertThrowsError(try LangSchwarzQuoteSource.decode(html, now: now)) { error in
            XCTAssertEqual(error as? LangSchwarzQuoteError, .noFreshQuotes)
        }
    }

    func testWallstreetOnlineConvertsUSDWithFreshFXAndRejectsStaleFX() throws {
        let page = wsoPage(price: "112,00", currency: "USD", time: "11:59:30")
        let rate = try WallstreetOnlineQuoteSource.decodeEURUSD(
            Data(wsoPage(price: "1,1200", currency: "USD", time: "11:59:30").utf8), now: now
        )
        let quote = try WallstreetOnlineQuoteSource.decode(Data(page.utf8), instrumentID: "/aktien/example-aktie",
                                                             euroUSD: rate, now: now)
        XCTAssertEqual(quote.priceEUR, 100, accuracy: 0.0001)
        XCTAssertEqual(quote.sourceCurrency, "USD")
        XCTAssertThrowsError(try WallstreetOnlineQuoteSource.decode(
            Data(page.utf8), instrumentID: "/aktien/example-aktie",
            euroUSD: (rate.rate, rate.observedAt - 6 * 60_000), now: now
        ))
    }

    private func row(wkn: String, item: String, bid: String, ask: String, time: String) -> String {
        """
        <tr><td><div>\(wkn)</div></td><td><a href="/de/aktie/example-aktie">Example AG</a></td>
        <td><span item="\(item)@1" field="bidWithCurrencySymbol">\(bid)</span></td>
        <td><span item="\(item)@1" field="askWithCurrencySymbol">\(ask)</span></td>
        <td></td><td></td><td><span field="midTime">\(time)</span></td></tr>
        """
    }

    private func wsoPage(price: String, currency: String, time: String) -> String {
        """
        <div class="marketchange" currency="$"><div class="float-start quoteValue"><span>\(price)</span></div>
        <div table="quotes" class="quote_currency">\(currency)</div>
        <span data-push=";ls;quotes;123@1@1;tt">\(time)</span>
        <div class="float-start askbidBox"></div>
        """
    }
}
