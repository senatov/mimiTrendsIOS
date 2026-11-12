import XCTest
@testable import MiMiTrends

final class RapidRiseDetectorTests: XCTestCase {
    func testConfirmedReversalUsesBreakoutClose() throws {
        let now: Int64 = 13_000
        let bars = prices("RISE", endingAt: now, [102, 101, 100, 100.8, 100.4, 101.1])
        let signal = try XCTUnwrap(RapidRiseDetector.detect(symbol: "RISE", bars: bars, nowEpochSeconds: now))
        XCTAssertEqual(signal.windowChangePercent, 1.1, accuracy: 1e-9)
        XCTAssertEqual(signal.signalEpochMillis, now * 1_000)
        XCTAssertEqual(signal.signalPrice, 100)
        XCTAssertEqual(signal.price, 101.1)
        XCTAssertEqual(signal.signalSource, "Confirmed reversal")
        XCTAssertNil(signal.priceAnomaly)
        XCTAssertNil(signal.rangeAnomaly)
        XCTAssertNoThrow(try JSONEncoder().encode(signal))
    }

    func testRecoveredSpikeDoesNotCountAsCurrentRebound() {
        let now: Int64 = 13_000
        let bars = prices("RECOVERED", endingAt: now, [100, 100.1, 101.8, 100.4])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "RECOVERED", bars: bars, nowEpochSeconds: now))
    }

    func testMicronBounceHasNoHigherLowAndBreakout() {
        let now: Int64 = 13_000
        let bars = prices("MU", endingAt: now,
                          [795.57, 793.925, 791.64, 790.03, 786.155, 791.635,
                           788.97, 784.793, 783.647, 782.057, 783.38, 782.9,
                           781.32, 776.56, 775.765, 772.685, 773.895, 776.385, 778.945])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "MU", bars: bars, nowEpochSeconds: now))
    }

    func testBreakoutMustBeCurrentAndFollowAnActualDecline() {
        let now: Int64 = 13_000
        XCTAssertNil(RapidRiseDetector.detect(symbol: "RALLY", bars: prices("RALLY", endingAt: now,
            [100, 100.2, 100, 100.8, 100.4, 101.1]), nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "EARLY", bars: prices("EARLY", endingAt: now,
            [102, 101, 100, 100.8, 100.4, 100.7]), nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "LATE", bars: prices("LATE", endingAt: now,
            [102, 101, 100, 100.8, 100.4, 101.1, 101.2]), nowEpochSeconds: now))
    }

    func testThinMissingAndStaleBarsDoNotSignal() {
        let now: Int64 = 13_000
        let closes = [102.0, 101, 100, 100.8, 100.4, 101.1]
        let thin = prices("THIN", endingAt: now, closes, volume: 1)
        let missing = prices("MISSING", endingAt: now, closes, status: .missing)
        let stale = prices("STALE", endingAt: now - 660, closes)
        XCTAssertNil(RapidRiseDetector.detect(symbol: "THIN", bars: thin, nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "MISSING", bars: missing, nowEpochSeconds: now))
        XCTAssertNil(RapidRiseDetector.detect(symbol: "STALE", bars: stale, nowEpochSeconds: now))
    }

    func testDelayedGermanCandlesKeepOriginalEventTime() throws {
        let now: Int64 = 13_000
        let bars = prices("SAP.DE", endingAt: now - 900, [102, 101, 100, 100.8, 100.4, 101.1])
        XCTAssertNil(RapidRiseDetector.detect(symbol: "SAP.DE", bars: bars, nowEpochSeconds: now))
        let signal = try XCTUnwrap(RapidRiseDetector.detect(
            symbol: "SAP.DE", bars: bars,
            nowEpochSeconds: RadarMarketDataPolicy.evaluationTime(symbol: "SAP.DE", now: now)
        ))
        XCTAssertEqual(signal.signalEpochMillis, (now - 900) * 1_000)
        XCTAssertEqual(signal.priceCurrency, "EUR")
        XCTAssertEqual(RadarMarketDataPolicy.evaluationTime(symbol: "AAPL", now: now), now)
        let stale = prices("SAP.DE", endingAt: now - 86_400, [102, 101, 100, 100.8, 100.4, 101.1])
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
