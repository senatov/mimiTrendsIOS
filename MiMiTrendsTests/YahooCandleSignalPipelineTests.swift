import Foundation
import XCTest
@testable import MiMiTrends

final class YahooCandleSignalPipelineTests: XCTestCase {
    private let now: Int64 = 1_794_331_200 // 2026-11-10 17:20 UTC

    func testLegacyYahooAPIHostsMigrateWithoutReplacingCustomRanking() {
        let suite = "YahooEndpoints-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("https://query1.finance.yahoo.com/", forKey: "provider.endpoint.yahooPrimary.v1")
        defaults.set("https://finance.yahoo.com/markets/stocks/trending/", forKey: "provider.endpoint.yahooAlternate.v1")
        XCTAssertEqual(ProviderEndpointStore.url(for: .yahooPrimary, defaults: defaults).absoluteString,
                       ProviderEndpoint.yahooPrimary.defaultURL)
        XCTAssertEqual(ProviderEndpointStore.url(for: .yahooAlternate, defaults: defaults).absoluteString,
                       "https://finance.yahoo.com/markets/stocks/trending/")
    }

    func testYahooRankingPagesSupplyDeduplicatedSupportedSymbols() {
        let html = """
        <table><tr><td><a href="/quote/NVDA/">NVDA</a></td></tr>
        <tr><td><a href='https://finance.yahoo.com/quote/BRK-B/'>Berkshire Hathaway</a></td></tr>
        <tr><td><a href="/quote/NVDA/">NVIDIA</a></td></tr>
        <tr><td><a href="/quote/BTC-USD/">Bitcoin</a></td></tr></table>
        """
        let candidates = YahooRankingPageSource.candidates(in: html)
        XCTAssertEqual(candidates.map(\.symbol), ["NVDA", "BRK-B"])
    }

    func testCompletedDropCreatesVolumeBackedSignalAndIsVisible() throws {
        let bars = history(symbol: "NVDA", end: now - 60, dropping: true)
        let signal = try XCTUnwrap(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: bars,
            nowEpochSeconds: now, settings: RadarScanPreferences()))
        XCTAssertEqual(signal.signalSource, "Rapid crash")
        XCTAssertEqual(signal.dataStatus, YahooCandleSignalPipeline.currentStatus)
        XCTAssertGreaterThan(signal.windowVolume, 0)
        XCTAssertEqual(signal.signalEpochMillis, (now - 60) * 1_000)
        let display = RadarSignalSelection.displayHistory([signal], since: 0, limit: 10)
        XCTAssertEqual(display.signals.count, 1)
    }

    func testUnfinishedCandleCannotCreateSignal() {
        var bars = history(symbol: "NVDA", end: now - 60, dropping: false)
        bars.append(MinuteBar(symbol: "NVDA", minuteEpochSeconds: now,
                              open: 100, high: 100, low: 90, close: 90, volume: 100_000))
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: bars,
            nowEpochSeconds: now, settings: RadarScanPreferences()))
    }

    func testOldCandlesMissingVolumeAndRecoveredDropsDoNotTriggerCrash() {
        let stale = history(symbol: "NVDA", end: now - 600, dropping: true)
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: stale,
            nowEpochSeconds: now, settings: RadarScanPreferences()))
        let missing = history(symbol: "NVDA", end: now - 60, dropping: true).map {
            MinuteBar(symbol: $0.symbol, minuteEpochSeconds: $0.minuteEpochSeconds,
                      open: $0.open, high: $0.high, low: $0.low, close: $0.close,
                      volume: 0, volumeStatus: .missing)
        }
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: missing,
            nowEpochSeconds: now, settings: RadarScanPreferences()))
        let recovered = history(symbol: "NVDA", end: now - 60, dropping: true) + [
            MinuteBar(symbol: "NVDA", minuteEpochSeconds: now, open: 98, high: 100, low: 98, close: 100, volume: 10_000),
            MinuteBar(symbol: "NVDA", minuteEpochSeconds: now + 60, open: 100, high: 100, low: 100, close: 100, volume: 10_000)
        ]
        let signal = YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: recovered,
            nowEpochSeconds: now + 120, settings: RadarScanPreferences())
        XCTAssertNotEqual(signal?.signalSource, "Rapid crash")
    }

    func testGermanDelayKeepsOriginalEventTimeAndMarketCloseSkipsDetection() throws {
        let actualNow = Int64(ISO8601DateFormatter().date(from: "2026-11-10T14:00:00Z")!.timeIntervalSince1970)
        let end = actualNow - 900 - 60
        let bars = history(symbol: "SAP.DE", end: end, dropping: true)
        let signal = try XCTUnwrap(YahooCandleSignalPipeline.detect(symbol: "SAP.DE", bars: bars,
            nowEpochSeconds: actualNow, settings: RadarScanPreferences()))
        XCTAssertEqual(signal.dataStatus, YahooCandleSignalPipeline.delayedStatus)
        XCTAssertEqual(signal.signalEpochMillis, end * 1_000)
        XCTAssertEqual(signal.signalAgeMinutes, 16)
        XCTAssertEqual(signal.scanEvaluatedAtMillis, actualNow * 1_000)
        let closed = Int64(ISO8601DateFormatter().date(from: "2026-11-10T18:00:00Z")!.timeIntervalSince1970)
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "SAP.DE", bars: bars,
            nowEpochSeconds: closed, settings: RadarScanPreferences()))
    }

    func testPoolFills200DeduplicatesAndExcludesClosedGermanMarket() {
        let us = (0..<240).map { "US\($0)" }
        let german = (0..<120).map { "DE\($0).DE" }
        let pool = RadarScanPool.symbols(baseline: ["US1", "DE1.DE"], yahoo: Array(us.prefix(100)),
            secondary: us, german: german, germanOpen: false, excluded: ["US2"])
        XCTAssertEqual(pool.count, 200)
        XCTAssertEqual(Set(pool).count, 200)
        XCTAssertFalse(pool.contains("US2"))
        XCTAssertFalse(pool.contains { $0.hasSuffix(".DE") })
        let mixed = RadarScanPool.symbols(baseline: [], yahoo: us, secondary: [], german: german, germanOpen: true)
        XCTAssertEqual(mixed.count, 200)
        XCTAssertTrue(mixed.contains("DE0.DE"))
        XCTAssertTrue(mixed.contains("US0"))
    }

    func testDAXRanksBothDirectionsAndSkipsStaleRows() {
        let html = """
        <h2>Kursliste Realtime Dax-Aktien</h2>
        <table>
        <tr><td><a href="/aktien/SAP-Aktie/DE0007164600">SAP</a></td>
          <td>177,68</td><td>5,32</td><td>3,09</td><td>09:08:00</td></tr>
        <tr><td><a href="/aktien/Rheinmetall-Aktie/DE0007030009">Rheinmetall</a></td>
          <td>1.145,00</td><td>-48,00</td><td>−4,00</td><td>09:09:00</td></tr>
        <tr><td><a href="/aktien/Siemens-Aktie/DE0007236101">Siemens</a></td>
          <td>280,20</td><td>7,10</td><td>2,60</td><td>08:30:00</td></tr>
        </table>
        """
        let now = ISO8601DateFormatter().date(from: "2026-11-11T08:10:00Z")!
        let rows = BoerseDAXSource.rows(in: html, now: now)
        XCTAssertEqual(rows.map(\.isin), ["DE0007030009", "DE0007164600"])
        XCTAssertEqual(rows.map(\.change), [-4, 3.09])
    }

    func testBothMarketsSwitchIndependentlyAcrossHolidaysAndDST() {
        let formatter = ISO8601DateFormatter()
        func sessions(_ utc: String) -> RadarTradingSessions {
            RadarTradingSessions(at: formatter.date(from: utc)!)
        }

        let beforeGermanOpen = sessions("2026-11-11T07:45:00Z")
        XCTAssertEqual(beforeGermanOpen.german, .preMarket)
        XCTAssertTrue(beforeGermanOpen.germanOpeningSoon)
        XCTAssertEqual(beforeGermanOpen.us, .closed)

        let beforeUSOpen = sessions("2026-10-28T13:15:00Z")
        XCTAssertEqual(beforeUSOpen.german, .regular)
        XCTAssertEqual(beforeUSOpen.us, .preMarket)
        XCTAssertTrue(beforeUSOpen.usOpeningSoon)
        XCTAssertEqual(sessions("2026-10-28T13:30:00Z").us, .regular)

        let earlyUSClose = sessions("2026-11-27T18:00:00Z")
        XCTAssertEqual(earlyUSClose.german, .afterHours)
        XCTAssertEqual(earlyUSClose.us, .afterHours)
        XCTAssertEqual(sessions("2026-11-27T22:00:00Z").us, .closed)
        XCTAssertEqual(sessions("2026-11-26T16:00:00Z").us, .closed)
        XCTAssertEqual(sessions("2026-11-26T16:00:00Z").german, .regular)
        XCTAssertEqual(sessions("2026-04-06T14:00:00Z").german, .closed)
        XCTAssertEqual(sessions("2026-12-30T13:00:00Z").german, .closed)
        XCTAssertEqual(sessions("2026-11-28T15:00:00Z").us, .closed)
    }

    func testClosedUSMarketLeavesGermanCandidatesInScanPool() {
        let pool = RadarScanPool.symbols(baseline: ["NVDA", "SAP.DE"], yahoo: ["AAPL"],
            secondary: ["MSFT"], german: ["SAP.DE", "RHM.DE"], germanOpen: true, usOpen: false)
        XCTAssertEqual(pool, ["SAP.DE", "RHM.DE"])
    }

    private func history(symbol: String, end: Int64, dropping: Bool) -> [MinuteBar] {
        (0..<31).map { index in
            let close = dropping && index >= 29 ? 100 - Double(index - 28) : 100
            return MinuteBar(symbol: symbol, minuteEpochSeconds: end - Int64(30 - index) * 60,
                open: close, high: close + 0.1, low: close - 0.1, close: close, volume: 10_000)
        }
    }
}
