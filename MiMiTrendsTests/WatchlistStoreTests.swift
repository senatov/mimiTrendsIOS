import Foundation
import SQLite3
import XCTest
@testable import MiMiTrends

final class WatchlistStoreTests: XCTestCase {
    func testNormalizationDuplicateOrderingRemovalAndReopen() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try WatchlistStore(url: url)

        let first = try await store.add(" aapl ", atMillis: 2_000)
        let second = try await store.add("msft", atMillis: 1_000)
        let third = try await store.add("brk.b", atMillis: 1_000)
        let repeated = try await store.add("AAPL", atMillis: 3_000)
        let loaded = try await store.load()
        XCTAssertTrue(first)
        XCTAssertTrue(second)
        XCTAssertTrue(third)
        XCTAssertFalse(repeated)
        XCTAssertEqual(loaded.map(\.symbol), ["BRK.B", "MSFT", "AAPL"])

        try await store.remove(" msft ")
        let reopened = try WatchlistStore(url: url)
        let loadedAgain = try await reopened.load()
        XCTAssertEqual(loadedAgain.map(\.symbol), ["BRK.B", "AAPL"])
    }

    func testInvalidSymbolsAreRejected() throws {
        for value in ["", "   ", "A APL", "A/B", String(repeating: "A", count: 33)] {
            XCTAssertThrowsError(try WatchlistStore.normalize(value))
        }
    }

    func testRenamePreservesOrderAndRejectsDuplicate() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try WatchlistStore(url: url)
        try await store.add("AAPL", atMillis: 1_000)
        try await store.add("MSFT", atMillis: 2_000)

        try await store.rename("aapl", to: " nvda ")
        let renamed = try await store.load()
        XCTAssertEqual(renamed.map(\.symbol), ["NVDA", "MSFT"])
        XCTAssertEqual(renamed.first?.addedAtMillis, 1_000)

        do {
            try await store.rename("NVDA", to: "MSFT")
            XCTFail("Duplicate symbol was accepted")
        } catch WatchlistStoreError.duplicateSymbol {
            let unchanged = try await store.load()
            XCTAssertEqual(unchanged.map(\.symbol), ["NVDA", "MSFT"])
        }
    }

    func testFutureSchemaIsRejected() throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try WatchlistStore(url: url)
        var connection: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &connection), SQLITE_OK)
        defer { if let connection { sqlite3_close(connection) } }
        XCTAssertEqual(sqlite3_exec(
            connection, "INSERT INTO native_schema_migrations(version, applied_at) VALUES (2, 0)",
            nil, nil, nil
        ), SQLITE_OK)
        XCTAssertThrowsError(try WatchlistStore(url: url)) { error in
            guard case WatchlistStoreError.unsupportedSchema = error else {
                return XCTFail("Wrong schema error")
            }
        }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-watchlist-tests-\(UUID().uuidString)")
            .appendingPathComponent("watchlist.db")
    }
}
