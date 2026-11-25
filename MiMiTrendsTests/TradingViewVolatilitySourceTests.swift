import XCTest
@testable import MiMiTrends

final class TradingViewVolatilitySourceTests: XCTestCase {
    func testScreenerKeepsLiquidSupportedSharesAndRanksActivity() throws {
        let data = Data(#"""
        {"data":[
          {"s":"NASDAQ:FAST","d":["FAST","Fast Inc.","NASDAQ",20,300000,2,500000000,8,"US0000000001"]},
          {"s":"NYSE:MOVE","d":["MOVE","Move Corp.","NYSE",30,100000,1,600000000,6,"US0000000002"]},
          {"s":"OTC:OTCX","d":["OTCX","OTC Inc.","OTC",20,300000,2,500000000,9]},
          {"s":"NASDAQ:THIN","d":["THIN","Thin Inc.","NASDAQ",20,1000,2,500000000,20]},
          {"s":"NASDAQ:CHEAP","d":["CHEAP","Cheap Inc.","NASDAQ",2,3000000,2,500000000,20]}
        ]}
        """#.utf8)
        let result = try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates)
        XCTAssertEqual(result.map(\.company.symbol), ["FAST", "MOVE"])
        XCTAssertEqual(result.map(\.company.isin), ["US0000000001", "US0000000002"])
    }

    func testShortDropRankingRejectsGainsAndMissingChanges() throws {
        let data = Data(#"""
        {"data":[
          {"s":"NASDAQ:LQDA","d":["LQDA","Liquidia","NASDAQ",55,300000,0.1,500000000,4,"US53635D2027",-4.2]},
          {"s":"NYSE:MOVE","d":["MOVE","Move Corp.","NYSE",30,100000,1,600000000,6,"US0000000002",-1.2]},
          {"s":"NYSE:GAIN","d":["GAIN","Gain Corp.","NYSE",30,100000,1,600000000,6,"US0000000003",4.5]},
          {"s":"NYSE:NONE","d":["NONE","None Corp.","NYSE",30,100000,1,600000000,6,"US0000000004",null]}
        ]}
        """#.utf8)
        for minutes in [5, 15] {
            let result = try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates,
                                                                       ranking: .shortDrop(minutes))
            XCTAssertEqual(result.map(\.company.symbol), ["LQDA", "MOVE"])
        }
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

    func testActiveScreenerKeepsLargeLiquidSharesWithoutVolatilityThreshold() throws {
        let data = Data(#"""
        {"data":[
          {"s":"NYSE:KO","d":["KO","Coca-Cola Company (The)","NYSE",65,12000000,0.4,280000000000,0.7,"US1912161007"]},
          {"s":"NASDAQ:INTC","d":["INTC","Intel Corporation","NASDAQ",35,50000000,0.3,150000000000,0.8,"US4581401001"]},
          {"s":"NASDAQ:THIN","d":["THIN","Thin Inc.","NASDAQ",12,100,0.2,500000000,2,"US0000000001"]},
          {"s":"OTC:OTHER","d":["OTHER","Other Inc.","OTC",25,1000000,1,500000000,5,"US0000000002"]}
        ]}
        """#.utf8)
        let result = try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates,
                                                                    ranking: .activity)
        XCTAssertEqual(result.map(\.company.symbol), ["INTC", "KO"])
        XCTAssertEqual(result.map(\.company.isin), ["US4581401001", "US1912161007"])
        XCTAssertTrue(try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates).isEmpty)
    }

    func testMostVolatileRiseLaneIncludesLiquidCueBelowOldPriceAndCapFloors() throws {
        let data = Data(#"""
        {"data":[
          {"s":"NASDAQ:CUE","d":["CUE","Cue Biopharma, Inc.","NASDAQ",4.53,11780000,20.23,37830000,56.88,"US22978P2056",59.89]},
          {"s":"NASDAQ:THIN","d":["THIN","Thin Inc.","NASDAQ",4.53,1000,20,37830000,60,"US0000000001",50]},
          {"s":"NASDAQ:SMALL","d":["SMALL","Small Inc.","NASDAQ",4.53,11780000,20,1000000,60,"US0000000002",50]}
        ]}
        """#.utf8)
        let selected = try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates,
                                                                      ranking: .strongRise)
        XCTAssertEqual(selected.map(\.company.symbol), ["CUE"])
        XCTAssertEqual(selected.first?.company.isin, "US22978P2056")
        XCTAssertTrue(try TradingViewVolatilitySource.parseScanJSON(data, market: .unitedStates).isEmpty)
    }

    func testGermanMostVolatileRiseLaneUsesGermanTurnoverFloor() throws {
        let data = Data(#"""
        {"data":[
          {"s":"XETR:CA1","d":["CA1","Circus SE","XETR",8.4,127770,2,223500000,17.4,"DE0000000001",13.5]},
          {"s":"XETR:THIN","d":["THIN","Thin AG","XETR",8.4,100,2,223500000,20,"DE0000000002",15]}
        ]}
        """#.utf8)
        let selected = try TradingViewVolatilitySource.parseScanJSON(data, market: .germany,
                                                                      ranking: .strongRise)
        XCTAssertEqual(selected.map(\.company.symbol), ["CA1.DE"])
    }
}
