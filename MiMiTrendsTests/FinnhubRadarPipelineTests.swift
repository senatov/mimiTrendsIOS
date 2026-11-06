import Foundation
import XCTest
@testable import MiMiTrends

final class FinnhubRadarPipelineTests: XCTestCase {
    func testConfiguredRiseThresholdChangesPublishedSignals() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-threshold-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        var settings = RadarScanPreferences()
        settings.risePercent = 2.0
        let pipeline = try FinnhubRadarPipeline(
            databaseURL: directory.appendingPathComponent("market.db"), settings: settings
        )
        var last: FinnhubRadarPipeline.Update?
        for (second, price) in [(12_000, 100.0), (12_060, 100.1),
                                (12_120, 101.8), (12_180, 101.8)] {
            last = try await pipeline.accept(
                TradeTick(symbol: "RISE", price: price,
                          timestampMillis: Int64(second) * 1_000 + 1, volume: 1_000),
                nowEpochSeconds: Int64(second)
            )
        }
        XCTAssertNil(last?.signal)
    }

    func testTradesBecomeStoredBarsAndRapidRiseSignal() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-pipeline-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("market.db")
        let pipeline = try FinnhubRadarPipeline(databaseURL: url)
        let observations: [(Int64, Double)] = [
            (12_000, 100), (12_060, 100.1), (12_120, 101.8), (12_180, 101.8)
        ]
        var updates: [FinnhubRadarPipeline.Update] = []
        for (second, price) in observations {
            let trade = TradeTick(
                symbol: "RISE", price: price,
                timestampMillis: second * 1_000 + 1, volume: 1_000
            )
            updates.append(try await pipeline.accept(trade, nowEpochSeconds: second))
        }
        XCTAssertEqual(updates.filter(\.storedBar).count, 3)
        XCTAssertNil(updates[0].signal)
        XCTAssertEqual(updates[3].signal?.windowChangePercent ?? 0, 1.8, accuracy: 1e-9)
        XCTAssertTrue(updates[3].storedSignal)

        let store = try MarketBarStore(url: url)
        let saved = try await store.loadMinuteBars(symbol: "RISE", fromEpochSeconds: 0)
        XCTAssertEqual(saved.map(\.minuteEpochSeconds), [12_000, 12_060, 12_120])
        XCTAssertEqual(saved.map(\.volumeStatus), [.reported, .reported, .reported])
        let signals = try MarketSignalStore(url: directory.appendingPathComponent("mimitrends-signals.db"))
        let history = try await signals.loadRecent()
        XCTAssertEqual(history, [try XCTUnwrap(updates[3].signal)])
    }

    func testFreshWideQuoteSuppressesSignalBeforePersistence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mimitrends-quality-tests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let pipeline = try FinnhubRadarPipeline(databaseURL: directory.appendingPathComponent("market.db"))
        let observations: [(Int64, Double)] = [
            (12_000, 100), (12_060, 100.1), (12_120, 101.8), (12_180, 101.8)
        ]
        var finalUpdate: FinnhubRadarPipeline.Update?
        for (second, price) in observations {
            let trade = TradeTick(
                symbol: "RISE", price: price,
                timestampMillis: second * 1_000 + 1, volume: 1_000
            )
            finalUpdate = try await pipeline.accept(
                trade, nowEpochSeconds: second,
                quote: second == 12_180 ? quote(observedAtMillis: second * 1_000) : nil,
                marketCurrency: "USD"
            )
        }
        XCTAssertNil(finalUpdate?.signal)
        XCTAssertEqual(finalUpdate?.storedSignal, false)
        let store = try MarketSignalStore(url: directory.appendingPathComponent("mimitrends-signals.db"))
        let history = try await store.loadRecent()
        XCTAssertTrue(history.isEmpty)
    }

    private func quote(observedAtMillis: Int64) -> ProviderQuoteSnapshot {
        ProviderQuoteSnapshot(
            provider: "TEST", symbol: "RISE", identifier: "instrument",
            currency: "USD", last: 101.8, bid: 100, ask: 104,
            bidSize: nil, askSize: nil, sessionVolume: nil,
            sessionTurnover: nil, averagePrice: nil, executions: nil,
            sessionHigh: nil, sessionLow: nil, previousClose: nil,
            observedAtMillis: observedAtMillis
        )
    }
}
