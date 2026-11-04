import Foundation
import XCTest
@testable import MiMiTrends

private actor FetchCounter {
    private(set) var calls = 0

    func fetch(_ symbol: String) -> [MinuteBar] {
        calls += 1
        return [MinuteBar(symbol: symbol, minuteEpochSeconds: 60,
                          open: 100, high: 101, low: 99, close: 100, volume: 1_000)]
    }
}

final class RadarSignalBarBackfillTests: XCTestCase {
    func testExistingBarsDoNotTriggerNetworkFetch() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try MarketBarStore(url: url)
        _ = try await store.upsert(MinuteBar(
            symbol: "AAPL", minuteEpochSeconds: 60,
            open: 100, high: 101, low: 99, close: 100, volume: 1_000
        ))
        let counter = FetchCounter()
        let backfill = RadarSignalBarBackfill(storeURL: url, fetchBars: { await counter.fetch($0) })

        let changed = await backfill.fillIfMissing(symbol: "aapl")
        let callCount = await counter.calls

        XCTAssertFalse(changed)
        XCTAssertEqual(callCount, 0)
    }

    func testMissingBarsAreFetchedOnceAndSaved() async throws {
        let url = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let counter = FetchCounter()
        let backfill = RadarSignalBarBackfill(storeURL: url, fetchBars: { await counter.fetch($0) })

        let changed = await backfill.fillIfMissing(symbol: "aapl")
        let changedAgain = await backfill.fillIfMissing(symbol: "AAPL")
        let store = try MarketBarStore(url: url)
        let saved = try await store.loadMinuteBars(symbol: "AAPL", fromEpochSeconds: 0)
        let callCount = await counter.calls

        XCTAssertTrue(changed)
        XCTAssertFalse(changedAgain)
        XCTAssertEqual(saved.count, 1)
        XCTAssertEqual(callCount, 1)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-backfill-tests-\(UUID().uuidString)")
            .appendingPathComponent("market.db")
    }
}
