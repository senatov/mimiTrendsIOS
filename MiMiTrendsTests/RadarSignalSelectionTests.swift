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

    func testRestoresOlderSignalsOnlyWhenNoFreshSignalsExist() {
        let history = [event("OLD", source: "Rapid rise", at: 100),
                       event("NEW", source: "Rapid crash", at: 300)]

        let restored = RadarSignalSelection.displayHistory(history, since: 400, limit: 10)
        XCTAssertTrue(restored.savedFallback)
        XCTAssertEqual(restored.signals.map(\.symbol), ["NEW", "OLD"])

        let fresh = RadarSignalSelection.displayHistory(history, since: 200, limit: 10)
        XCTAssertFalse(fresh.savedFallback)
        XCTAssertEqual(fresh.signals.map(\.symbol), ["NEW"])
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

        XCTAssertEqual(displayed.signals.map(\.symbol), ["AAPL", "MSFT"])
    }

    private func event(
        _ symbol: String, source: String, at epoch: Int64,
        change: Double = 1, window: String = "1m"
    ) -> ScanResult {
        ScanResult(
            symbol: symbol, price: 100, anomalyScore: 0,
            priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
            relativeVolume: nil, candleBodyRatio: 0,
            windowChangePercent: change, windowVolume: 0, sessionVolume: 0,
            sessionTurnover: 0, signalAgeMinutes: 0, signalSource: source,
            updatedAtMillis: epoch, signalWindowLabel: window, signalEpochMillis: epoch
        )
    }
}
