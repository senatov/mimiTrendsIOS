import XCTest
@testable import MiMiTrends

final class RapidRiseDetectorTests: XCTestCase {
    func testSharpReboundUsesLatestClose() throws {
        let now: Int64 = 13_000
        let bars = prices("RISE", endingAt: now, [100, 100.1, 100.5, 101.8])
        let signal = try XCTUnwrap(RapidRiseDetector.detect(symbol: "RISE", bars: bars, nowEpochSeconds: now))
        XCTAssertEqual(signal.windowChangePercent, 1.8, accuracy: 1e-9)
        XCTAssertEqual(signal.signalEpochMillis, now * 1_000)
        XCTAssertEqual(signal.signalPrice, 100)
        XCTAssertEqual(signal.price, 101.8)
        XCTAssertEqual(signal.signalSource, "Sharp rebound")
        XCTAssertNil(signal.priceAnomaly)
        XCTAssertNil(signal.rangeAnomaly)
        XCTAssertNoThrow(try JSONEncoder().encode(signal))
    }

    func testRecoveredSpikeDoesNotCountAsCurrentRebound() {
        let now: Int64 = 13_000
        let bars = prices("RECOVERED", endingAt: now, [100, 100.1, 101.8, 100.4])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "RECOVERED", bars: bars, nowEpochSeconds: now))
    }

    func testThinMissingAndStaleBarsDoNotSignal() {
        let now: Int64 = 13_000
        let thin = prices("THIN", endingAt: now, [100, 100.1, 101.8, 100.4], volume: 1)
        let missing = prices("MISSING", endingAt: now, [100, 100.1, 101.8, 100.4], status: .missing)
        let stale = prices("STALE", endingAt: now - 660, [100, 100.1, 101.8, 100.4])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "THIN", bars: thin, nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "MISSING", bars: missing, nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "STALE", bars: stale, nowEpochSeconds: now))
    }

    func testDelayedGermanCandlesKeepOriginalEventTime() throws {
        let now: Int64 = 13_000
        let bars = prices("SAP.DE", endingAt: now - 900, [100, 100.1, 100.5, 101.8])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "SAP.DE", bars: bars, nowEpochSeconds: now))
        let signal = try XCTUnwrap(RapidRiseDetector.detect(
            symbol: "SAP.DE", bars: bars,
            nowEpochSeconds: RadarMarketDataPolicy.evaluationTime(symbol: "SAP.DE", now: now)
        ))
        XCTAssertEqual(signal.signalEpochMillis, (now - 900) * 1_000)
        XCTAssertEqual(signal.priceCurrency, "EUR")
        XCTAssertEqual(RadarMarketDataPolicy.evaluationTime(symbol: "AAPL", now: now), now)
        let stale = prices("SAP.DE", endingAt: now - 86_400, [100, 100.1, 100.5, 101.8])
        XCTAssertNil(RapidRiseDetector.detect(
            symbol: "SAP.DE", bars: stale,
            nowEpochSeconds: RadarMarketDataPolicy.evaluationTime(symbol: "SAP.DE", now: now)
        ))
    }

    private func prices(
        _ symbol: String, endingAt end: Int64, _ closes: [Double],
        volume: Double = 1_000, status: VolumeStatus = .reported
    ) -> [MinuteBar] {
        closes.enumerated().map { index, close in
            MinuteBar(
                symbol: symbol, minuteEpochSeconds: end - Int64(closes.count - 1 - index) * 60,
                open: close, high: close, low: close, close: close,
                volume: volume, volumeStatus: status
            )
        }
    }
}
