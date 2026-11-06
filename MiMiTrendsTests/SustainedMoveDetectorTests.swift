import XCTest
@testable import MiMiTrends

final class SustainedMoveDetectorTests: XCTestCase {
    func testSmoothGradualRiseIsDetected() throws {
        let now: Int64 = 80_000
        let bars = prices("AAPL", now: now, volume: 20_000) { 100 + Double($0) * 0.02 }

        let signal = try XCTUnwrap(SmoothRiseDetector.detect(
            symbol: "AAPL", bars: bars, nowEpochSeconds: now
        ))
        XCTAssertEqual(signal.signalSource, "Smooth rise")
        XCTAssertEqual(signal.anomalyScore, 90)
        XCTAssertEqual(signal.windowChangePercent, 1.2, accuracy: 1e-9)
        XCTAssertEqual(signal.signalWindowLabel, "60m")
        XCTAssertEqual(signal.signalPrice, 100)
    }

    func testGradualDropDoesNotEmitSmoothRise() {
        let now: Int64 = 80_000
        let bars = prices("DROP", now: now, volume: 20_000) { 101.2 - Double($0) * 0.02 }

        XCTAssertNil(SmoothRiseDetector.detect(
            symbol: "DROP", bars: bars, nowEpochSeconds: now
        ))
    }

    func testChoppyGainIsNotReportedAsSmoothRise() {
        let now: Int64 = 80_000
        let bars = prices("CHOPPY", now: now, volume: 20_000) { minute in
            100 + Double(minute) * 0.02 + ((minute / 5).isMultiple(of: 2) ? 0.30 : 0)
        }

        XCTAssertNil(SmoothRiseDetector.detect(
            symbol: "CHOPPY", bars: bars, nowEpochSeconds: now
        ))
    }

    func testSingleSharpSpikeIsNotReportedAsSmoothRise() {
        let now: Int64 = 80_000
        let bars = prices("SPIKE", now: now, volume: 20_000) { $0 == 60 ? 102 : 100 }

        XCTAssertNil(SmoothRiseDetector.detect(
            symbol: "SPIKE", bars: bars, nowEpochSeconds: now
        ))
    }

    func testThinMissingStaleAndSparseBarsAreRejected() {
        let now: Int64 = 80_000
        let thin = prices("THIN", now: now, volume: 100) { 100 + Double($0) * 0.02 }
        let missing = thin.map { bar in
            MinuteBar(symbol: bar.symbol, minuteEpochSeconds: bar.minuteEpochSeconds,
                      open: bar.open, high: bar.high, low: bar.low, close: bar.close,
                      volume: 0, volumeStatus: .missing)
        }
        let stale = prices("STALE", now: now - 660, volume: 20_000) { 100 + Double($0) * 0.02 }
        let sparse = prices("SPARSE", now: now, volume: 20_000) { 100 + Double($0) * 0.02 }
            .filter { $0.minuteEpochSeconds <= now - 1_800 || $0.minuteEpochSeconds >= now - 1_440 }

        XCTAssertNil(SmoothRiseDetector.detect(symbol: "THIN", bars: thin, nowEpochSeconds: now))
        XCTAssertNil(SmoothRiseDetector.detect(symbol: "THIN", bars: missing, nowEpochSeconds: now))
        XCTAssertNil(SmoothRiseDetector.detect(symbol: "STALE", bars: stale, nowEpochSeconds: now))
        XCTAssertNil(SmoothRiseDetector.detect(symbol: "SPARSE", bars: sparse, nowEpochSeconds: now))
    }

    private func prices(
        _ symbol: String, now: Int64, volume: Double,
        close: (Int) -> Double
    ) -> [MinuteBar] {
        (0...60).map { minute in
            let price = close(minute)
            return MinuteBar(
                symbol: symbol, minuteEpochSeconds: now - Int64(60 - minute) * 60,
                open: price, high: price, low: price, close: price,
                volume: volume, volumeStatus: .reported
            )
        }
    }
}
