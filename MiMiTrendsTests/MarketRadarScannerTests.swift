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
            ["symbol": "LOW", "quoteType": "EQUITY", "regularMarketVolume": 10],
            ["symbol": "HIGH", "quoteType": "EQUITY", "regularMarketVolume": 100],
            ["symbol": "FUND", "quoteType": "ETF", "regularMarketVolume": 1_000],
            ["symbol": "ZERO", "quoteType": "EQUITY", "regularMarketVolume": 0],
            ["symbol": "HIGH", "quoteType": "EQUITY", "regularMarketVolume": 100]
        ]
        XCTAssertEqual(YahooRadarSource.activeSymbols(in: quotes, limit: 3), ["HIGH", "LOW"])
    }

    func testFMPCandidatesDiscardInvalidRowsAndInterleaveMoverLists() throws {
        let data = Data("""
        [
          {"symbol":"AAPL","name":"Apple Inc.","price":200,"exchange":"NASDAQ"},
          {"symbol":"PENNY","name":"Penny Corp.","price":0.5,"exchange":"OTC"},
          {"symbol":"BAD","name":"", "price":10,"exchange":"NYSE"},
          {"symbol":"MSFT","name":"Microsoft Corp.","price":400,"exchange":"NASDAQ"}
        ]
        """.utf8)
        let active = try FMPCandidateSource.decodeCandidates(data)
        XCTAssertEqual(active.map(\.symbol), ["AAPL", "MSFT"])
        let movers = FMPCandidateSource.interleave(
            [active, [active[0], RadarCompanyCandidate(symbol: "NVDA", name: "Nvidia")]], limit: 3
        )
        XCTAssertEqual(movers.map(\.symbol), ["AAPL", "MSFT", "NVDA"])
        XCTAssertThrowsError(try FMPCandidateSource.decodeCandidates(Data("{}".utf8)))
    }

    func testFMPProfileAcceptsOnlyMatchingCompanyAndProviderImage() {
        let data = Data("""
        [{"symbol":"AAPL","companyName":"Apple Inc.","country":"US",
          "image":"https://images.financialmodelingprep.com/symbol/AAPL.png","defaultImage":false}]
        """.utf8)
        let profile = FMPCompanyProfileSource.decode(data, symbol: "AAPL")
        XCTAssertEqual(profile?.name, "Apple Inc.")
        XCTAssertEqual(profile?.countryCode, "US")
        XCTAssertEqual(profile?.logoURL?.host, "images.financialmodelingprep.com")
        XCTAssertNil(FMPCompanyProfileSource.decode(data, symbol: "MSFT"))

        let placeholder = Data("""
        [{"symbol":"AAPL","image":"https://images.financialmodelingprep.com/symbol/AAPL.png",
          "defaultImage":true}]
        """.utf8)
        XCTAssertNil(FMPCompanyProfileSource.decode(placeholder, symbol: "AAPL")?.logoURL)
    }

    func testYahooBarDecoderSkipsIncompleteCandles() throws {
        let root: [String: Any] = ["chart": ["result": [[
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
