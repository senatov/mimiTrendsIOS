import XCTest
@testable import MiMiTrends

final class MarketRadarScannerTests: XCTestCase {
    func testInterleavesDistinctSymbolsFromBothDiscoverySources() {
        XCTAssertEqual(
            MarketRadarScanner.interleave(["AAPL", "MSFT", "NVDA"], ["NVDA", "TSLA", "AMD"], limit: 5),
            ["AAPL", "NVDA", "MSFT", "TSLA", "AMD"]
        )
    }

    func testYahooScanRotatesAcrossBoundedBatches() {
        let symbols = ["A", "B", "C", "D", "E", "F"]
        XCTAssertEqual(MarketRadarScanner.scanSlice(symbols, offset: 0, limit: 4), ["A", "B", "C", "D"])
        XCTAssertEqual(MarketRadarScanner.scanSlice(symbols, offset: 4, limit: 4), ["E", "F", "A", "B"])
        XCTAssertEqual(MarketRadarScanner.scanSlice([], offset: 0, limit: 4), [])
    }

    func testInitialScanDoesNotRecheckSymbolsWhenRejectedCandidatesLeavePool() {
        let remaining = ["A", "D", "E", "F", "G", "H"]
        let batch = MarketRadarScanner.scanBatch(
            remaining, processed: ["A", "B", "C", "D"], offset: 4, limit: 4
        )
        XCTAssertEqual(batch, ["E", "F", "G", "H"])
    }

    func testYahooRateLimitDoesNotRetryAlternateHost() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [YahooRateLimitURLProtocol.self]
        let session = URLSession(configuration: configuration)
        YahooRateLimitURLProtocol.reset()

        do {
            _ = try await YahooRadarSource(session: session).minuteBars(symbol: "AAPL")
            XCTFail("Expected HTTP 429 to stop Yahoo requests")
        } catch RadarSourceError.rateLimited {
            XCTAssertEqual(YahooRateLimitURLProtocol.requestCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testYahooMostActiveSelectionRequiresEquitiesWithVolume() {
        let quotes: [[String: Any]] = [
            ["symbol": "LOW", "quoteType": "EQUITY", "regularMarketVolume": 30_000,
             "regularMarketPrice": 100, "exchange": "NMS", "currency": "USD"],
            ["symbol": "HIGH", "quoteType": "EQUITY", "regularMarketVolume": 100_000,
             "regularMarketPrice": 100, "exchange": "NMS", "currency": "USD"],
            ["symbol": "FUND", "quoteType": "ETF", "regularMarketVolume": 1_000_000,
             "regularMarketPrice": 100, "exchange": "NMS", "currency": "USD"],
            ["symbol": "ZERO", "quoteType": "EQUITY", "regularMarketVolume": 0,
             "regularMarketPrice": 100, "exchange": "NMS", "currency": "USD"],
            ["symbol": "HIGH", "quoteType": "EQUITY", "regularMarketVolume": 100_000,
             "regularMarketPrice": 100, "exchange": "NMS", "currency": "USD"]
        ]
        XCTAssertEqual(YahooRadarSource.activeSymbols(in: quotes, limit: 3), ["HIGH", "LOW"])
    }

    func testYahooCandidatesRejectOtherMarketsAndIlliquidShares() {
        let quotes: [[String: Any]] = [
            ["symbol": "SAP.DE", "shortName": "SAP SE", "quoteType": "EQUITY",
             "regularMarketPrice": 250, "regularMarketVolume": 20_000,
             "exchange": "GER", "currency": "EUR"],
            ["symbol": "SHOP.TO", "shortName": "Shopify Inc.", "quoteType": "EQUITY",
             "regularMarketPrice": 100, "regularMarketVolume": 500_000,
             "exchange": "TOR", "currency": "CAD"],
            ["symbol": "THIN", "shortName": "Thin Inc.", "quoteType": "EQUITY",
             "regularMarketPrice": 10, "regularMarketVolume": 1_000,
             "exchange": "NMS", "currency": "USD"],
            ["symbol": "AAPL", "shortName": "Apple Inc.", "quoteType": "EQUITY",
             "regularMarketPrice": 200, "regularMarketVolume": 50_000,
             "exchange": "NMS", "currency": "USD"],
            ["symbol": "ADR", "shortName": "Foreign Depositary Receipt", "quoteType": "EQUITY",
             "regularMarketPrice": 80, "regularMarketVolume": 40_000,
             "exchange": "NMS", "currency": "USD", "country": "CA"]
        ]
        XCTAssertEqual(YahooRadarSource.activeSymbols(in: quotes, limit: 10), ["AAPL", "ADR", "SAP.DE"])
    }

    func testGermanTraderFoxCandidatesBecomeYahooSymbolsAndRejectStaleRows() throws {
        let now: Int64 = 1_800_000_000
        let html = """
        <script>var equities = {
          "1":{"active":"Y","currency":"EUR","symbol":"SAP","name":"SAP SE","v":250,"p":5,"t":1800000000},
          "2":{"active":"Y","currency":"EUR","symbol":"SIE","name":"Siemens AG","v":220,"p":3,"t":1800000000},
          "3":{"active":"Y","currency":"USD","symbol":"AAPL","name":"Apple Inc.","v":200,"p":8,"t":1800000000},
          "4":{"active":"Y","currency":"EUR","symbol":"OLD","name":"Old SE","v":25,"p":9,"t":1700000000},
          "5":{"active":"N","currency":"EUR","symbol":"OFF","name":"Inactive AG","v":40,"p":7,"t":1800000000}
        };</script>
        """
        XCTAssertEqual(
            try TraderFoxRadarSource.decodeGermanCandidates(html, limit: 10, nowSeconds: now)
                .map(\.symbol),
            ["SAP.DE", "SIE.DE"]
        )
    }

    func testGermanMarketSessionUsesBerlinWeekdaysAndXetraHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        func date(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 11, day: day,
                                               hour: hour, minute: minute))!
        }

        XCTAssertTrue(GermanMarketSession.isOpen(at: date(5, 9, 0)))
        XCTAssertTrue(GermanMarketSession.isOpen(at: date(5, 17, 29)))
        XCTAssertFalse(GermanMarketSession.isOpen(at: date(5, 8, 59)))
        XCTAssertFalse(GermanMarketSession.isOpen(at: date(5, 17, 30)))
        XCTAssertFalse(GermanMarketSession.isOpen(at: date(7, 12, 0)))
    }

    func testYahooBarDecoderSkipsIncompleteCandles() throws {
        let root: [String: Any] = ["chart": ["result": [[
            "meta": ["currency": "USD"],
            "timestamp": [120, 180],
            "indicators": ["quote": [[
                "open": [10.0, NSNull()], "high": [11.0, 11.0],
                "low": [9.0, 9.0], "close": [10.5, 10.5],
                "volume": [100, 0]
            ]]]
        ]]]]
        let bars = try YahooRadarSource.decodeBars(root, symbol: "AAPL")
        XCTAssertEqual(bars.count, 1)
        XCTAssertEqual(bars.first?.minuteEpochSeconds, 120)
        var wrongCurrency = root
        var chart = wrongCurrency["chart"] as! [String: Any]
        var results = chart["result"] as! [[String: Any]]
        results[0]["meta"] = ["currency": "EUR"]
        chart["result"] = results
        wrongCurrency["chart"] = chart
        XCTAssertThrowsError(try YahooRadarSource.decodeBars(wrongCurrency, symbol: "AAPL"))
        XCTAssertEqual(try YahooRadarSource.decodeBars(wrongCurrency, symbol: "SAP.DE").count, 1)
    }

    func testTraderFoxFiltersStaleAndInactiveRows() throws {
        let now: Int64 = 1_800_000_000
        let html = """
        <script>var equities = {
          "1":{"active":"Y","currency":"USD","symbol":"AAPL","v":200,"p":2.5,"t":1800000000},
          "2":{"active":"N","currency":"USD","symbol":"OFF","v":20,"p":7,"t":1800000000},
          "3":{"active":"Y","currency":"USD","symbol":"OLD","v":20,"p":8,"t":1700000000}
        };</script>
        """
        XCTAssertEqual(try TraderFoxRadarSource.decode(html, limit: 10, nowSeconds: now), ["AAPL"])
    }
}

private final class YahooRateLimitURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        count = 0
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.count += 1
        Self.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: 429,
                                       httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
