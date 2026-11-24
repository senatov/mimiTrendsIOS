import XCTest
@testable import MiMiTrends

final class RadarSignalSelectionTests: XCTestCase {
    func testSparklineUsesOnlyRealMinuteClosesBeforeEvent() throws {
        let eventSecond: Int64 = 3_600
        let bars = [2_700, 2_760, 3_000, 3_480, 3_540, 3_600, 3_660].enumerated().map { index, minute in
            MinuteBar(symbol: "SAP.DE", minuteEpochSeconds: Int64(minute),
                      open: Double(100 + index), high: Double(100 + index),
                      low: Double(100 + index), close: Double(100 + index), volume: 100)
        }
        let series = try XCTUnwrap(RadarSparklineSeries(bars: bars, eventMillis: eventSecond * 1_000))
        XCTAssertEqual(series.points.map(\.minute), [2_700, 2_760, 3_000, 3_480, 3_540, 3_600])
        XCTAssertEqual(series.highlightedFrom, 2)
        XCTAssertEqual(series.changePercent, 5, accuracy: 0.001)
    }

    func testSparklineDoesNotInventHistoryFromTwoCandles() {
        let bars = [MinuteBar(symbol: "SAP.DE", minuteEpochSeconds: 3_540,
                              open: 100, high: 100, low: 100, close: 100, volume: 100),
                    MinuteBar(symbol: "SAP.DE", minuteEpochSeconds: 3_600,
                              open: 101, high: 101, low: 101, close: 101, volume: 100)]
        XCTAssertNil(RadarSparklineSeries(bars: bars, eventMillis: 3_600_000))
    }

    func testKeepsNewestEventForEachSymbol() {
        let signals = [
            event("AAPL", source: "Sustained rise", at: 60),
            event("MSFT", source: "Rapid crash", at: 120),
            event("AAPL", source: "Rapid rise", at: 180)
        ]

        let selected = RadarSignalSelection.latestPerSymbol(signals, limit: 2)

        XCTAssertEqual(selected.map(\.symbol), ["AAPL", "MSFT"])
        XCTAssertEqual(selected.first?.signalSource, "Rapid rise")
    }

    func testExcludesOlderSignalsWhenNoFreshSignalsExist() {
        let history = [event("OLD", source: "Rapid rise", at: 100),
                       event("NEW", source: "Rapid crash", at: 300, change: -2.2)]

        let expired = RadarSignalSelection.displayHistory(history, since: 400, limit: 10)
        XCTAssertTrue(expired.isEmpty)

        let fresh = RadarSignalSelection.displayHistory(history, since: 200, limit: 10)
        XCTAssertEqual(fresh.map(\.symbol), ["NEW"])
    }

    func testHidesSavedRapidDropsBelowCurrentThresholds() {
        let history = [
            event("NVDA", source: "Rapid crash", at: 300, change: -0.63, window: "5m"),
            event("FIS", source: "Rapid crash", at: 295, change: -1.14, window: "10m"),
            event("AMZN", source: "Rapid crash", at: 292, change: -0.78, window: "15m"),
            event("AAPL", source: "Rapid crash", at: 290, change: -2.0, window: "5m"),
            event("MSFT", source: "Confirmed reversal", at: 280, change: 0.8, window: "5m")
        ]

        let displayed = RadarSignalSelection.displayHistory(history, since: 0, limit: 10,
                                                           nowMillis: 500_000)

        XCTAssertEqual(displayed.map(\.symbol), ["AAPL", "MSFT"])
    }

    func testHidesLegacyRapidDropsWithoutValidatedCandles() {
        let legacyYahoo = event("DELL", source: "Rapid crash", at: 500, change: -1.02,
                                window: "4m", dataStatus: "LIVE")

        let displayed = RadarSignalSelection.displayHistory([legacyYahoo], since: 0, limit: 10)

        XCTAssertTrue(displayed.isEmpty)
    }

    func testHidesOldUnconfirmedReboundsEvenWithValidatedCandles() {
        let old = event("MU", source: "Sharp rebound", at: 500, change: 0.81,
                        window: "3m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let new = event("AAPL", source: "Confirmed reversal", at: 490, change: 1.1,
                        window: "5m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        XCTAssertEqual(RadarSignalSelection.displayHistory([old, new], since: 0, limit: 10,
                                                           nowMillis: 500_000)
            .map(\.symbol), ["AAPL"])
    }

    func testHidesReversalAfterNewCloseLosesFirstLow() {
        let signal = event("MU", source: "Confirmed reversal", at: 60_000, change: 1,
                           window: "5m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let failedBar = MinuteBar(symbol: "MU", minuteEpochSeconds: 120,
                                  open: 100, high: 100, low: 99, close: 99, volume: 1_000)
        let selected = RadarSignalSelection.displayHistory([signal], since: 0, limit: 10,
            latestBars: ["MU": failedBar], nowMillis: 180_000)
        XCTAssertTrue(selected.isEmpty)
    }

    func testHidesMarvellReversalWhenLaterCloseLosesBreakout() {
        let signal = ScanResult(symbol: "MRVL", price: 129.71, priceCurrency: "USD",
            anomalyScore: 0, priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
            relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: 0.824,
            windowVolume: 1_000, sessionVolume: 1_000, sessionTurnover: 129_710,
            signalAgeMinutes: 0, signalSource: "Confirmed reversal",
            updatedAtMillis: 1_795_536_540_000,
            dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus,
            signalWindowLabel: "3m", signalPrice: 128.65,
            signalEpochMillis: 1_795_536_540_000)
        let later = MinuteBar(symbol: "MRVL", minuteEpochSeconds: 1_795_538_220,
                              open: 128.92, high: 129.18, low: 128.66,
                              close: 128.91, volume: 43_409)
        let now: Int64 = 1_795_538_280_000

        XCTAssertTrue(RadarSignalSelection.displayHistory([signal], since: 0, limit: 10,
            latestBars: ["MRVL": later], nowMillis: now).isEmpty)
        XCTAssertTrue(RadarSignalSelection.displayHistory([signal], since: 0, limit: 10,
            nowMillis: now).isEmpty)
        XCTAssertEqual(RadarSignalSelection.displayHistory([signal], since: 0, limit: 10,
            nowMillis: signal.signalEpochMillis + 300_000).map(\.symbol), ["MRVL"])
    }

    func testNewerYahooCandleRemovesRecoveredCrashAndOlderSignalForSameStock() {
        let recent = event("MU", source: "Rapid crash", at: 120_000, change: -1,
                           window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let older = event("MU", source: "Rapid crash", at: 60_000, change: -1,
                          window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let recovered = MinuteBar(symbol: "MU", minuteEpochSeconds: 180,
            open: 99, high: 102, low: 99, close: 101, volume: 1_000)
        let shown = RadarSignalSelection.displayHistory([recent, older], since: 0, limit: 10,
            latestBars: ["MU": recovered], nowMillis: 240_000)
        XCTAssertTrue(shown.isEmpty)
    }

    func testRecoveredOlderCrashDoesNotHideNewerValidCrash() {
        let old = event("MU", source: "Rapid crash", at: 60_000, change: -1,
                        window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus,
                        anchor: 90)
        let new = ScanResult(symbol: "MU", price: 95, anomalyScore: 0,
            priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil, relativeVolume: nil,
            candleBodyRatio: 0, windowChangePercent: -1, windowVolume: 1_000,
            sessionVolume: 1_000, sessionTurnover: 95_000, signalAgeMinutes: 0,
            signalSource: "Rapid crash", updatedAtMillis: 120_000,
            dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus,
            signalWindowLabel: "4m", signalPrice: 100, signalEpochMillis: 120_000)
        let latest = MinuteBar(symbol: "MU", minuteEpochSeconds: 180,
            open: 95, high: 96, low: 94, close: 95, volume: 1_000)
        let shown = RadarSignalSelection.displayHistory([old, new], since: 0, limit: 10,
            latestBars: ["MU": latest], nowMillis: 240_000)
        XCTAssertEqual(shown.map(\.signalEpochMillis), [120_000])
    }

    func testMultiHourRiseExpiresWhenFreshPriceLosesMostOfItsGain() {
        let signal = ScanResult(symbol: "CUE", price: 4.20, priceCurrency: "USD",
            anomalyScore: 85, priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
            relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: 31.25,
            windowVolume: 1_000_000, sessionVolume: 1_000_000,
            sessionTurnover: 4_000_000, signalAgeMinutes: 0,
            signalSource: MultiHourRiseDetector.source, updatedAtMillis: 120_000,
            dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus,
            signalWindowLabel: "180m", signalPrice: 3.20, signalEpochMillis: 120_000)
        let latest = MinuteBar(symbol: "CUE", minuteEpochSeconds: 180,
            open: 3.60, high: 3.60, low: 3.60, close: 3.60, volume: 50_000)
        XCTAssertTrue(RadarSignalSelection.displayHistory([signal], since: 0, limit: 10,
            latestBars: ["CUE": latest], nowMillis: 240_000).isEmpty)
    }

    func testDisplaysOnlyVolumeValidatedYahooCandles() {
        let raw = event("DELL", source: "Rapid crash", at: 500, change: -1.2,
                        window: "4m", dataStatus: YahooCandleSignalPipeline.currentStatus)
        let validated = event("AAPL", source: "Rapid crash", at: 500, change: -1.2,
                             window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let tooLong = event("NOK", source: "Smooth rise", at: 500, change: 2.1,
                            window: "71m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        XCTAssertEqual(RadarSignalSelection.displayHistory([raw, validated, tooLong], since: 0, limit: 10)
            .map(\.symbol), ["AAPL"])
    }

    func testLegacyLiveFeedSignalsAreHidden() {
        let old = event("NVDA", source: "Rapid crash", at: 500, change: -1.2,
                        window: "4m", dataStatus: "FINNHUB_LIVE")
        XCTAssertTrue(RadarSignalSelection.displayHistory([old], since: 0, limit: 10).isEmpty)
    }

    func testQuoteOnlySignalsAreExcludedFromCandleRadar() {
        let quote = event("LS:43763", source: "L&S quote rise", at: 500,
                          dataStatus: "QUOTE_NO_VOLUME")
        let boerseQuote = event("AXON", source: "boerse.de price drop", at: 500,
                                dataStatus: "BOERSE_PRICE_NO_VOLUME")
        let candle = event("NVDA", source: "Rapid crash", at: 500, change: -1.2,
                           window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let displayed = RadarSignalSelection.displayHistory([quote, boerseQuote, candle], since: 0, limit: 10)
        XCTAssertEqual(displayed.map(\.symbol), ["NVDA"])
    }

    func testValidatedSignalRemainsEligibleWhenTradingViewRankingRotates() {
        let saved = event("AEM", source: "Rapid crash", at: 500, change: -1.2,
            window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let quoteOnly = event("OTHER", source: "boerse.de price drop", at: 500,
            dataStatus: "BOERSE_PRICE_NO_VOLUME")
        XCTAssertTrue(RadarSignalSelection.hasVerifiedOrigin(saved, currentSymbols: []))
        XCTAssertFalse(RadarSignalSelection.hasVerifiedOrigin(quoteOnly, currentSymbols: []))
    }

    func testGermanWatchRelaxesThresholdUntilThreeRecentCandidatesQualify() {
        let now = ISO8601DateFormatter().date(from: "2026-11-18T14:45:00Z")!
        let evaluation = RadarMarketDataPolicy.evaluationTime(
            symbol: "SAP.DE", now: Int64(now.timeIntervalSince1970))
        func bars(_ symbol: String, _ latest: Double, offset: Int64 = 60) -> [MinuteBar] {
            [MinuteBar(symbol: symbol, minuteEpochSeconds: evaluation - 300,
                       open: 100, high: 100, low: 100, close: 100, volume: 1_000),
             MinuteBar(symbol: symbol, minuteEpochSeconds: evaluation - offset,
                       open: latest, high: latest, low: latest, close: latest, volume: 1_000)]
        }
        let selected = RadarGermanWatchCandidates.select(barsBySymbol: [
            "SAP.DE": bars("SAP.DE", 99.45),
            "DBK.DE": bars("DBK.DE", 99.58),
            "SIE.DE": bars("SIE.DE", 100.38),
            "RHM.DE": bars("RHM.DE", 99.8),
            "BAS.DE": bars("BAS.DE", 98.5, offset: 900)
        ], now: now, settings: RadarScanPreferences())
        XCTAssertEqual(selected.map(\.symbol), ["SAP.DE", "DBK.DE", "SIE.DE"])
        XCTAssertTrue(selected.allSatisfy { $0.dataStatus == RadarGermanWatchCandidates.dataStatus })
    }

    func testGermanReserveDisappearsWhenConfirmedGermanSignalExists() {
        let us = (0..<30).map { event("US\($0)", source: "Rapid crash", at: Int64(1_000 - $0)) }
        let watch = (0..<5).map {
            event("DE\($0).DE", source: RadarGermanWatchCandidates.source, at: 500,
                  dataStatus: RadarGermanWatchCandidates.dataStatus)
        }
        let fallback = RadarSignalSelection.withGermanReserve(us, watch: watch, limit: 30)
        XCTAssertEqual(fallback.count, 30)
        XCTAssertEqual(fallback.filter { $0.dataStatus == RadarGermanWatchCandidates.dataStatus }.count, 5)

        let real = event("SAP.DE", source: "Rapid crash", at: 400)
        let confirmed = RadarSignalSelection.withGermanReserve(us + [real], watch: watch, limit: 30)
        XCTAssertEqual(confirmed.count, 30)
        XCTAssertTrue(confirmed.contains { $0.symbol == "SAP.DE" })
        XCTAssertFalse(confirmed.contains { $0.dataStatus == RadarGermanWatchCandidates.dataStatus })
    }

    private func event(
        _ symbol: String, source: String, at epoch: Int64,
        change: Double = 1, window: String = "1m", dataStatus: String? = nil,
        anchor: Double = 100
    ) -> ScanResult {
        ScanResult(
            symbol: symbol, price: 100, anomalyScore: 0,
            priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
            relativeVolume: nil, candleBodyRatio: 0,
            windowChangePercent: change, windowVolume: 0, sessionVolume: 0,
            sessionTurnover: 0, signalAgeMinutes: 0, signalSource: source,
            updatedAtMillis: epoch,
            dataStatus: dataStatus ?? (["Rapid crash", "Rapid rise", "Confirmed reversal"].contains(source)
                ? YahooCandleSignalPipeline.volumeValidatedStatus : "CACHE"),
            signalWindowLabel: window, signalPrice: anchor, signalEpochMillis: epoch
        )
    }
}
