import XCTest
@testable import MiMiTrends

final class TradingViewVolatilitySourceTests: XCTestCase {
    func testScreenerKeepsLiquidSupportedSharesAndRanksActivity() throws {
        let data = Data(#"""
        {"data":[
          {"s":"NASDAQ:FAST","d":["FAST","Fast Inc.","NASDAQ",20,300000,2,500000000,8]},
          {"s":"NYSE:MOVE","d":["MOVE","Move Corp.","NYSE",30,100000,1,600000000,6]},
          {"s":"OTC:OTCX","d":["OTCX","OTC Inc.","OTC",20,300000,2,500000000,9]},
          {"s":"NASDAQ:THIN","d":["THIN","Thin Inc.","NASDAQ",20,1000,2,500000000,20]},
          {"s":"NASDAQ:CHEAP","d":["CHEAP","Cheap Inc.","NASDAQ",2,3000000,2,500000000,20]}
        ]}
        """#.utf8)
        let result = try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates)
        XCTAssertEqual(result.map(\.company.symbol), ["FAST", "MOVE"])
    }

    func testHTMLFallbackReadsXetraRowAndRejectsThinShare() {
        func row(_ ticker: String, _ price: String, _ volume: String) -> String {
            """
            <tr><td><a href="/symbols/XETR-\(ticker)/">\(ticker)</a><a href="/symbols/XETR-\(ticker)/">\(ticker) AG</a></td>
            <td>4.2%</td><td>\(price) EUR</td><td>+2%</td><td>\(volume)</td><td>1.5</td><td>500 M EUR</td></tr>
            """
        }
        let html = "<table><tbody>\(row("SAP", "200", "10 K"))\(row("TINY", "10", "1 K"))</tbody></table>"
        let result = TradingViewVolatilitySource.parse(html, market: .germany)
        XCTAssertEqual(result.map(\.company.symbol), ["SAP.DE"])
    }
}
