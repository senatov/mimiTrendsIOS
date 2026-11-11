import XCTest
@testable import MiMiTrends

final class RadarSignalSelectionTests: XCTestCase {
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
            event("MSFT", source: "Rapid rise", at: 280, change: 0.8, window: "5m")
        ]

        let displayed = RadarSignalSelection.displayHistory(history, since: 0, limit: 10)

        XCTAssertEqual(displayed.map(\.symbol), ["AAPL", "MSFT"])
    }

    func testHidesLegacyRapidDropsWithoutValidatedCandles() {
        let legacyYahoo = event("DELL", source: "Rapid crash", at: 500, change: -1.02,
                                window: "4m", dataStatus: "LIVE")

        let displayed = RadarSignalSelection.displayHistory([legacyYahoo], since: 0, limit: 10)

        XCTAssertTrue(displayed.isEmpty)
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
        let candle = event("NVDA", source: "Rapid crash", at: 500, change: -1.2,
                           window: "4m", dataStatus: YahooCandleSignalPipeline.volumeValidatedStatus)
        let displayed = RadarSignalSelection.displayHistory([quote, candle], since: 0, limit: 10)
        XCTAssertEqual(displayed.map(\.symbol), ["NVDA"])
    }

    private func event(
        _ symbol: String, source: String, at epoch: Int64,
        change: Double = 1, window: String = "1m", dataStatus: String? = nil
    ) -> ScanResult {
        ScanResult(
            symbol: symbol, price: 100, anomalyScore: 0,
            priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
            relativeVolume: nil, candleBodyRatio: 0,
            windowChangePercent: change, windowVolume: 0, sessionVolume: 0,
            sessionTurnover: 0, signalAgeMinutes: 0, signalSource: source,
            updatedAtMillis: epoch,
            dataStatus: dataStatus ?? (["Rapid crash", "Rapid rise"].contains(source)
                ? YahooCandleSignalPipeline.volumeValidatedStatus : "CACHE"),
            signalWindowLabel: window, signalEpochMillis: epoch
        )
    }
}
