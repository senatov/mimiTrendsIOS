import Foundation
import SQLite3
import XCTest
@testable import MiMiTrends

final class MarketSignalStoreTests: XCTestCase {
    func testSignalIsRecordedOnceAndSurvivesReopen() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketSignalStore(url: url)
        let signal = try XCTUnwrap(RapidRiseDetector.detect(
            symbol: "RISE", bars: bars(), nowEpochSeconds: 12_180
        ))

        let inserted = try await store.record(signal)
        let repeated = try await store.record(signal)
        let loaded = try await store.loadRecent()
        XCTAssertTrue(inserted)
        XCTAssertFalse(repeated)
        XCTAssertEqual(loaded, [signal])

        let reopened = try MarketSignalStore(url: url)
        let loadedAgain = try await reopened.loadRecent()
        XCTAssertEqual(loadedAgain, [signal])
    }

    func testFutureSchemaIsRejected() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try MarketSignalStore(url: url)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        XCTAssertEqual(sqlite3_exec(
            connection, "INSERT INTO native_schema_migrations(version, applied_at) VALUES (2, 0)",
            nil, nil, nil
        ), SQLITE_OK)
        XCTAssertThrowsError(try MarketSignalStore(url: url)) { error in
            guard case MarketSignalStoreError.unsupportedSchema = error else {
                return XCTFail("Wrong schema error")
            }
        }
    }

    func testRecentSignalsRespectAgeAndResultLimit() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketSignalStore(url: url)
        let old = try XCTUnwrap(RapidRiseDetector.detect(
            symbol: "OLD", bars: bars(symbol: "OLD", start: 12_000), nowEpochSeconds: 12_180
        ))
        let recent = try XCTUnwrap(RapidRiseDetector.detect(
            symbol: "NEW", bars: bars(symbol: "NEW", start: 24_000), nowEpochSeconds: 24_180
        ))
        _ = try await store.record(old)
        _ = try await store.record(recent)
        let limited = try await store.loadRecent(limit: 1)
        let ageFiltered = try await store.loadRecent(
            limit: 10, sinceEpochMillis: old.signalEpochMillis + 1
        )

        XCTAssertEqual(limited, [recent])
        XCTAssertEqual(ageFiltered, [recent])
    }

    func testValidatedYahooSignalDoesNotCollideWithLegacyEvent() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketSignalStore(url: url)
        func signal(status: String) -> ScanResult {
            ScanResult(symbol: "AAPL", price: 100, anomalyScore: 0,
                priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
                relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: -2,
                windowVolume: 1_000, sessionVolume: 1_000, sessionTurnover: 100_000,
                signalAgeMinutes: 0, signalSource: "Rapid crash", updatedAtMillis: 1_000,
                dataStatus: status, signalWindowLabel: "4m")
        }
        let liveInserted = try await store.record(signal(status: "FINNHUB_LIVE"))
        let yahooInserted = try await store.record(signal(status: YahooCandleSignalPipeline.volumeValidatedStatus))
        let loaded = try await store.loadRecent()
        XCTAssertTrue(liveInserted)
        XCTAssertTrue(yahooInserted)
        XCTAssertEqual(loaded.count, 2)
    }

    private func bars(symbol: String = "RISE", start: Int64 = 12_000) -> [MinuteBar] {
        [100.0, 100.1, 100.5, 101.8].enumerated().map { index, close in
            MinuteBar(
                symbol: symbol, minuteEpochSeconds: start + Int64(index) * 60,
                open: close, high: close, low: close, close: close,
                volume: 1_000
            )
        }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-signal-tests-\(UUID().uuidString)")
            .appendingPathComponent("signals.db")
    }
}
