import Foundation
import SQLite3
import XCTest
@testable import MiMiTrends

final class MarketBarStoreTests: XCTestCase {
    func testUpsertReloadAndReopen() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url, retentionEnabled: false)
        let original = MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 60,
            open: 100, high: 101, low: 99, close: 100.5, volume: 1_000
        )
        let inserted = try await store.upsert(original)
        let unchanged = try await store.upsert(original)
        XCTAssertTrue(inserted)
        XCTAssertFalse(unchanged)
        let updated = MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 60,
            open: 100, high: 102, low: 99, close: 101, volume: 1_200
        )
        let changed = try await store.upsert(updated)
        let loaded = try await store.loadMinuteBars(symbol: "aapl", fromEpochSeconds: 0)
        XCTAssertTrue(changed)
        XCTAssertEqual(loaded, [updated])

        let reopened = try MarketBarStore(url: url, retentionEnabled: false)
        let loadedAgain = try await reopened.loadMinuteBars(symbol: "AAPL", fromEpochSeconds: 0)
        XCTAssertEqual(loadedAgain, [updated])
    }

    func testInvalidBarIsRejectedAndFutureSchemaIsNotOpened() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url, retentionEnabled: false)
        let invalid = MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 60,
            open: 100, high: 100, low: 100, close: 100, volume: 0
        )
        do {
            _ = try await store.upsert(invalid)
            XCTFail("Invalid reported volume was accepted")
        } catch MarketBarStoreError.invalidBar {
            // Expected.
        }
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        XCTAssertEqual(sqlite3_exec(
            connection,
            "INSERT INTO native_schema_migrations(version, applied_at) VALUES (2, 0)",
            nil, nil, nil
        ), SQLITE_OK)
        XCTAssertThrowsError(try MarketBarStore(url: url, retentionEnabled: false)) { error in
            guard case MarketBarStoreError.unsupportedSchema = error else {
                return XCTFail("Wrong schema error")
            }
        }
    }

    func testRecentBarsAreBoundedAndChronological() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url, retentionEnabled: false)
        for minute in 1...5 {
            let bar = MinuteBar(
                symbol: "AAPL", minuteEpochSeconds: Int64(minute * 60),
                open: 100, high: 110, low: 99, close: Double(100 + minute), volume: 10
            )
            _ = try await store.upsert(bar)
        }
        let recent = try await store.loadRecentMinuteBars(
            symbol: " aapl ", fromEpochSeconds: 120, throughEpochSeconds: 300, limit: 2
        )
        XCTAssertEqual(recent.map(\.minuteEpochSeconds), [240, 300])
        XCTAssertEqual(recent.map(\.close), [104, 105])
    }

    func testBatchRejectsInvalidBarWithoutPartialWrites() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url, retentionEnabled: false)
        let valid = MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 60,
            open: 100, high: 101, low: 99, close: 100, volume: 1_000
        )
        let invalid = MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 120,
            open: 100, high: 101, low: 99, close: 100, volume: 0
        )
        do {
            _ = try await store.upsertBatch([valid, invalid])
            XCTFail("Invalid batch was accepted")
        } catch MarketBarStoreError.invalidBar {
            let loaded = try await store.loadMinuteBars(symbol: "AAPL", fromEpochSeconds: 0)
            XCTAssertTrue(loaded.isEmpty)
        }
    }

    func testRetentionKeepsOnlyRecentBars() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url)
        let minute = Int64(Date().timeIntervalSince1970 / 60) * 60
        let old = MinuteBar(symbol: "AAPL", minuteEpochSeconds: minute - 3_600,
                            open: 100, high: 101, low: 99, close: 100, volume: 10)
        let recent = MinuteBar(symbol: "AAPL", minuteEpochSeconds: minute - 60,
                               open: 101, high: 102, low: 100, close: 101, volume: 10)
        let changed = try await store.upsertBatch([old, recent])
        XCTAssertEqual(changed, 1)
        let loaded = try await store.loadMinuteBars(symbol: "AAPL", fromEpochSeconds: 0)
        XCTAssertEqual(loaded, [recent])
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-store-tests-\(UUID().uuidString)")
            .appendingPathComponent("market.db")
    }
}
