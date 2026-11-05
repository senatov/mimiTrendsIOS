import XCTest
@testable import MiMiTrends

final class RadarDailyHistoryServiceTests: XCTestCase {
    func testYahooHistoryNeedsNoFMPAndIsCached() async throws {
        let calls = DailyHistoryCalls()
        let bars = [bar]
        let service = RadarDailyHistoryService(yahoo: { _ in
            await calls.primary()
            return bars
        }, fmp: { _ in
            await calls.fallback()
            return nil
        })
        let first = try await service.load(symbol: "SAP.DE")
        let second = try await service.load(symbol: "SAP.DE")
        XCTAssertEqual(first.provider, "Yahoo")
        XCTAssertEqual(second.bars.count, 1)
        let counts = await calls.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 0)
    }

    func testConfiguredFallbackRetainsProviderAttribution() async throws {
        let bars = [bar]
        let service = RadarDailyHistoryService(yahoo: { _ in throw DailyHistoryError.unavailable },
                                               fmp: { _ in bars })
        let history = try await service.load(symbol: "SAP.DE")
        XCTAssertEqual(history.provider, "FMP")
        XCTAssertEqual(history.bars.count, 1)
    }

    func testUnavailableProvidersDoNotRequestARequiredKey() async {
        let service = RadarDailyHistoryService(yahoo: { _ in throw DailyHistoryError.unavailable },
                                               fmp: { _ in nil })
        do {
            _ = try await service.load(symbol: "SAP.DE")
            XCTFail("Expected history-unavailable error")
        } catch {
            XCTAssertFalse(error.localizedDescription.contains("API key"))
        }
    }

    private var bar: MinuteBar {
        MinuteBar(symbol: "SAP.DE", minuteEpochSeconds: 1_793_750_400,
                  open: 100, high: 102, low: 99, close: 101, volume: 1_000)
    }
}

private actor DailyHistoryCalls {
    private var yahoo = 0
    private var fmp = 0
    func primary() { yahoo += 1 }
    func fallback() { fmp += 1 }
    func counts() -> (Int, Int) { (yahoo, fmp) }
}
