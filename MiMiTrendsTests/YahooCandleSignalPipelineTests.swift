import Foundation
import XCTest
@testable import MiMiTrends

final class YahooCandleSignalPipelineTests: XCTestCase {
    private let now: Int64 = 1_794_331_200 // 2026-11-10 17:20 UTC

    func testChartCompanyNameReplacesTickerOnlyCandidateAndCache() {
        let name = YahooRadarSource.companyName(in: [
            "symbol": "CIFR", "longName": "Cipher Digital Inc.", "shortName": "CIFR"
        ], symbol: "CIFR")
        XCTAssertEqual(name, "Cipher Digital Inc.")
        XCTAssertEqual(RadarCompanyMetadataService.preferredName(
            symbol: "CIFR", candidate: "CIFR", cached: name), "Cipher Digital Inc.")
        XCTAssertEqual(RadarCompanyMetadataService.preferredName(
            symbol: "CIFR", candidate: "CIFR", cached: "CIFR"), "CIFR")
    }

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

    func testCompletedDropCreatesVolumeBackedSignalButIsExcludedFromLiveDisplay() throws {
        let bars = history(symbol: "NVDA", end: now - 60, dropping: true)
        let signal = try XCTUnwrap(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: bars,
            nowEpochSeconds: now, settings: RadarScanPreferences()))
        XCTAssertEqual(signal.signalSource, "Rapid crash")
        XCTAssertEqual(signal.dataStatus, YahooCandleSignalPipeline.currentStatus)
        XCTAssertGreaterThan(signal.windowVolume, 0)
        XCTAssertEqual(signal.signalEpochMillis, (now - 60) * 1_000)
        let display = RadarSignalSelection.displayHistory([signal], since: 0, limit: 10)
        XCTAssertTrue(display.isEmpty)
        let validated = try XCTUnwrap(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: bars,
            nowEpochSeconds: now, settings: RadarScanPreferences(), volumeValidated: true))
        XCTAssertEqual(validated.dataStatus, YahooCandleSignalPipeline.volumeValidatedStatus)
        XCTAssertEqual(RadarSignalSelection.displayHistory([validated], since: 0, limit: 10).count, 1)
    }

    func testVolumeValidationRejectsGappedOrMissingRecentCandles() {
        let bars = history(symbol: "NVDA", end: now - 60, dropping: true)
        let missing = bars.enumerated().map { index, bar in
            MinuteBar(symbol: bar.symbol, minuteEpochSeconds: bar.minuteEpochSeconds,
                open: bar.open, high: bar.high, low: bar.low, close: bar.close,
                volume: index == bars.count - 2 ? 0 : bar.volume,
                volumeStatus: index == bars.count - 2 ? .missing : .reported)
        }
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: missing,
            nowEpochSeconds: now, settings: RadarScanPreferences(), volumeValidated: true))
        let gapped = Array(bars.dropLast(3)) + [bars.last!]
        XCTAssertNil(YahooCandleSignalPipeline.detect(symbol: "NVDA", bars: gapped,
            nowEpochSeconds: now, settings: RadarScanPreferences(), volumeValidated: true))
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
        let validated = try XCTUnwrap(YahooCandleSignalPipeline.detect(symbol: "SAP.DE", bars: bars,
            nowEpochSeconds: actualNow, settings: RadarScanPreferences(), volumeValidated: true))
        XCTAssertEqual(validated.dataStatus, YahooCandleSignalPipeline.delayedVolumeValidatedStatus)
        XCTAssertEqual(RadarSignalSelection.displayHistory([validated], since: 0, limit: 10).count, 1)
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

    func testDAXRanksFreshMoversButKeepsStaleConstituents() throws {
        let json = """
        [
          {"text":["","SAP","A","177,68","177,68","177,68","5,32","3,09","","","","","09:08:00","STU"],"markup":"DE0007164600"},
          {"text":["","Rheinmetall","A","1145","1145","1145","-48","−4,00","","","","","09:09:00","STU"],"markup":"DE0007030009"},
          {"text":["","Siemens","A","280,20","280,20","280,20","7,10","2,60","","","","","08:30:00","STU"],"markup":"DE0007236101"}
        ]
        """
        let now = ISO8601DateFormatter().date(from: "2026-11-11T08:10:00Z")!
        let candidates = try BoerseDAXSource.decodePageRows(Data(json.utf8), now: now)
        XCTAssertEqual(candidates.map(\.symbol), ["RHM.DE", "SAP.DE", "SIE.DE"])
    }

    func testBoerseQuoteRowsReportWhyRenderedRowsAreNotUsable() {
        let now = ISO8601DateFormatter().date(from: "2026-11-12T15:30:00Z")!
        func row(time: String, venue: String) -> BoerseDAXSource.PageRow {
            BoerseDAXSource.PageRow(
                text: ["", "SAP", "A", "177,68", "177,68", "177,68", "5,32", "3,09",
                       "", "", "", "", time, venue], markup: "DE0007164600"
            )
        }
        let stale = BoerseQuoteRows.decode([row(time: "16:25:00", venue: "STU")], now: now, slot: 0)
        XCTAssertTrue(stale.samples.isEmpty)
        XCTAssertTrue(stale.diagnostics.contains("time=1 recent=0 accepted=0"))
        XCTAssertTrue(stale.diagnostics.contains("youngestAgeSeconds=300 timeSample=16:25:00"))
        XCTAssertNotNil(stale.newestQuoteMillis)

        let fresh = BoerseQuoteRows.decode([row(time: "16:29:30", venue: "STU")], now: now, slot: 0)
        XCTAssertEqual(fresh.samples.count, 1)
        XCTAssertEqual(fresh.samples.first?.symbol, "SAP.DE")
        XCTAssertTrue(fresh.diagnostics.contains("recent=1 accepted=1"))
        XCTAssertGreaterThan(fresh.newestQuoteMillis ?? 0, stale.newestQuoteMillis ?? 0)
    }

    func testBoerseRetriesLaggedOrStalledPagesWithoutReloadingEveryGap() {
        func reload(_ stale: TimeInterval, _ progress: TimeInterval, _ lastReload: TimeInterval,
                    _ quoteAge: Int?, unavailable: Bool = false) -> Bool {
            BoerseQuoteRetryPolicy.shouldReload(staleSeconds: stale, progressSeconds: progress,
                sinceReloadSeconds: lastReload, quoteAgeSeconds: quoteAge, pageUnavailable: unavailable)
        }
        XCTAssertFalse(reload(45, 45, 1_000, 360))
        XCTAssertTrue(reload(90, 15, 1_000, 360))
        XCTAssertFalse(reload(90, 15, 1_000, 100))
        XCTAssertTrue(reload(180, 180, 1_000, 100))
        XCTAssertFalse(reload(180, 180, 30, 360))
        XCTAssertTrue(reload(90, 90, 1_000, nil, unavailable: true))
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
