import Foundation
import SQLite3
import XCTest
@testable import MiMiTrends

final class MarketQuoteStoreTests: XCTestCase {
    func testLoadsLSBidAskHistoryInTimeOrder() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MarketQuoteStore(url: directory.appendingPathComponent("quotes.db"))
        let now: Int64 = 1_793_617_200_000
        let quotes = [now, now - 30_000].map { time in
            MarketPageQuote(identifier: "123", name: "Example", path: "/de/aktie/example",
                bidEUR: 100, askEUR: 100.1, sourceCurrency: "EUR", sourceBid: 100,
                sourceAsk: 100.1, euroUSDRate: nil, fxObservedAtMillis: nil, observedAtMillis: time)
        }
        _ = try await store.record(quotes.map(MarketQuoteRecord.init), nowMillis: now)
        let history = try await store.loadLS(sinceMillis: now - 60_000)
        XCTAssertEqual(history.map(\.observedAtMillis), [now - 30_000, now])
        XCTAssertEqual(history.first?.instrumentID, "123")
        XCTAssertEqual(history.first?.bid, 100)
        XCTAssertEqual(history.first?.ask, 100.1)
        let recent = try await store.loadLS(sinceMillis: now)
        XCTAssertEqual(recent.count, 1)
    }

    func testStoresOnlyConvertedEURQuotesAndDeduplicates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try MarketQuoteStore(url: directory.appendingPathComponent("quotes.db"))
        let now: Int64 = 1_793_617_200_000
        let converted = WallstreetOnlineQuote(
            instrumentID: "/aktien/example-aktie", priceEUR: 100,
            sourceCurrency: "USD", sourcePrice: 112, euroUSDRate: 1.12,
            fxObservedAtMillis: now - 10_000, observedAtMillis: now - 20_000
        )
        let record = MarketQuoteRecord(converted)
        let inserted = try await store.record([record], nowMillis: now)
        let duplicate = try await store.record([record], nowMillis: now)
        XCTAssertEqual(inserted, 1)
        XCTAssertEqual(duplicate, 0)
        let invalid = WallstreetOnlineQuote(
            instrumentID: converted.instrumentID, priceEUR: 112,
            sourceCurrency: "USD", sourcePrice: 112, euroUSDRate: nil,
            fxObservedAtMillis: nil, observedAtMillis: now
        )
        do {
            _ = try await store.record([MarketQuoteRecord(invalid)], nowMillis: now)
            XCTFail("Unconverted USD quote was stored")
        } catch MarketQuoteStoreError.invalidQuote {
            // The store must reject a quote without a valid conversion rate.
        }
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(directory.appendingPathComponent("quotes.db").path,
                                      &database, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { if let database { sqlite3_close(database) } }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(database,
            "SELECT price_eur, source_currency, eur_usd_rate FROM quote_observations",
            -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_double(statement, 0), 100, accuracy: 0.0001)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 1)), "USD")
        XCTAssertEqual(sqlite3_column_double(statement, 2), 1.12, accuracy: 0.0001)
        sqlite3_finalize(statement)

        _ = try await store.record([], nowMillis: now + 72 * 3_600_000 + 1)
        XCTAssertEqual(sqlite3_prepare_v2(database,
            "SELECT COUNT(*) FROM quote_observations", -1, &statement, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(sqlite3_column_int(statement, 0), 0)
        sqlite3_finalize(statement)
    }
}
