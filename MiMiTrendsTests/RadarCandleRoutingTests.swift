import Foundation
import XCTest
@testable import MiMiTrends

final class RadarCandleRoutingTests: XCTestCase {
    func testLSPageIdentityUsesISINNotCompanyName() throws {
        let html = "<title>NVIDIA CORP. DL-,001 Aktie | Aktienkurs | 918422 | US67066G1040</title>"
        XCTAssertEqual(try LSChartInstrumentResolver.isin(in: html), "US67066G1040")
        XCTAssertThrowsError(try LSChartInstrumentResolver.isin(in: "<title>NVIDIA CORP.</title>"))
    }

    func testISINSearchPrefersGermanListingForGermanISIN() throws {
        let data = Data(#"{"quotes":[{"symbol":"SAP","quoteType":"EQUITY"},{"symbol":"SAP.DE","quoteType":"EQUITY"},{"symbol":"SAP.F","quoteType":"EQUITY"}]}"#.utf8)
        XCTAssertEqual(try LSChartInstrumentResolver.yahooSymbol(in: data, isin: "DE0007164600"), "SAP.DE")
    }

    func testISINSearchRejectsAmbiguousResultsAndNonEquities() throws {
        let ambiguous = Data(#"{"quotes":[{"symbol":"AAPL","quoteType":"EQUITY"},{"symbol":"NVDA","quoteType":"EQUITY"}]}"#.utf8)
        XCTAssertThrowsError(try LSChartInstrumentResolver.yahooSymbol(in: ambiguous, isin: "US67066G1040"))
        let valid = Data(#"{"quotes":[{"symbol":"NVDA","quoteType":"EQUITY"},{"symbol":"WRONG","quoteType":"ETF"}]}"#.utf8)
        XCTAssertEqual(try LSChartInstrumentResolver.yahooSymbol(in: valid, isin: "US67066G1040"), "NVDA")
    }

    func testSelectedTickerOutsidePoolFetchesAndPersistsCandles() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("bars.db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let now = Date(timeIntervalSince1970: 1_794_320_000)
        let history = RadarSelectedCandleHistory(storeURL: url, fetch: { symbol in
            [MinuteBar(symbol: symbol, minuteEpochSeconds: 1_794_319_920,
                       open: 100, high: 102, low: 99, close: 101, volume: 1_000)]
        })
        let loaded = try await history.load(symbol: "NVDA", yahooEnabled: true, now: now)
        XCTAssertEqual(loaded.count, 1)
        let store = try MarketBarStore(url: url)
        let saved = try await store.loadMinuteBars(symbol: "NVDA", fromEpochSeconds: 0)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(saved.first?.close, 101)
    }

    func testDisabledYahooDoesNotFetchAndRateLimitDoesNotRetryImmediately() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("bars.db")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let counter = CandleFetchCounter()
        let history = RadarSelectedCandleHistory(storeURL: url, fetch: { _ in
            await counter.increment()
            throw RadarSourceError.rateLimited
        })
        let empty = try await history.load(symbol: "NVDA", yahooEnabled: false)
        XCTAssertTrue(empty.isEmpty)
        for _ in 0..<2 {
            do {
                _ = try await history.load(symbol: "NVDA", yahooEnabled: true)
                XCTFail("Expected rate limit")
            } catch RadarSourceError.rateLimited {} catch { XCTFail("Unexpected error: \(error)") }
        }
        let calls = await counter.calls
        XCTAssertEqual(calls, 1)
    }
}

private actor CandleFetchCounter {
    var calls = 0
    func increment() { calls += 1 }
}
