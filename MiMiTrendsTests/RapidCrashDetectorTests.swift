import XCTest
@testable import MiMiTrends

final class RapidCrashDetectorTests: XCTestCase {
    func testConfiguredShortDropThresholdIncludesBoundary() throws {
        let now: Int64 = 12_000
        let bars = prices("THRESHOLD", endingAt: now, [100, 100.15, 99.50, 99.0])
        let signal = try XCTUnwrap(RapidCrashDetector.detect(
            symbol: "THRESHOLD", bars: bars, nowEpochSeconds: now
        ))
        XCTAssertEqual(signal.signalSource, "Rapid crash")
        XCTAssertEqual(signal.windowChangePercent, -1.0, accuracy: 1e-9)
        XCTAssertEqual(signal.signalPrice, 100)
        XCTAssertEqual(signal.price, 99.0)
    }

    func testModeratePullbackDoesNotQualifyAsRapidCrash() {
        let now: Int64 = 12_000
        let bars = prices("PULLBACK", endingAt: now, [100, 99.85, 99.70, 99.37])
        XCTAssertNil(RapidCrashDetector.detect(symbol: "PULLBACK", bars: bars, nowEpochSeconds: now))
    }

    func testGradualDeclineNeedsAcceleration() throws {
        let ordinaryNow: Int64 = 40_000
        let ordinary = prices("ORDINARY", endingAt: ordinaryNow, [
            100, 99.95, 99.90, 99.85, 99.80, 99.75, 99.70, 99.65,
            99.60, 99.55, 99.50, 99.45, 99.40, 99.35, 99.30, 99.20
        ])
        XCTAssertNil(RapidCrashDetector.detect(
            symbol: "ORDINARY", bars: ordinary, nowEpochSeconds: ordinaryNow
        ))

        let acceleratingNow: Int64 = 41_000
        let accelerating = prices("ACCELERATING", endingAt: acceleratingNow, [
            100, 99.94, 99.88, 99.82, 99.76, 99.70, 99.64, 99.58,
            99.52, 99.46, 99.40, 99.40, 99.40, 99.20, 98.80, 98.41
        ])
        let signal = try XCTUnwrap(RapidCrashDetector.detect(
            symbol: "ACCELERATING", bars: accelerating, nowEpochSeconds: acceleratingNow
        ))
        XCTAssertEqual(signal.windowChangePercent, -1.59, accuracy: 1e-9)
    }

    func testSpikeReversalNeedsBreakOfPrecedingLow() throws {
        let now: Int64 = 60_000
        let rebound = [100.0, 101.0, 100.8, 100.4, 100.2]
        let times = [now - 300, now - 180, now - 120, now - 60, now]
        let bars = zip(times, rebound).map { time, price in
            bar("SPIKE", time, price)
        }
        XCTAssertNil(RapidCrashDetector.detect(symbol: "SPIKE", bars: bars, nowEpochSeconds: now))

        let breakBars = zip(times, [100.0, 101.0, 100.8, 100.4, 98.5]).map { time, price in
            bar("BREAK", time, price)
        }
        let signal = try XCTUnwrap(RapidCrashDetector.detect(
            symbol: "BREAK", bars: breakBars, nowEpochSeconds: now
        ))
        XCTAssertLessThan(signal.windowChangePercent, -1.5)
    }

    func testThinMissingAndStaleCrashesAreRejected() {
        let now: Int64 = 42_000
        let thin = prices("THIN", endingAt: now, [75, 74.9, 74.8, 74.7], volume: 10)
        let missing = prices("MISSING", endingAt: now, [100, 99.9, 99.8, 99.6],
                             volume: 0, status: .missing)
        let stale = prices("STALE", endingAt: now - 660, [100, 99.9, 99.8, 99.6])
        XCTAssertNil(RapidCrashDetector.detect(symbol: "THIN", bars: thin, nowEpochSeconds: now))
        XCTAssertNil(RapidCrashDetector.detect(symbol: "MISSING", bars: missing, nowEpochSeconds: now))
        XCTAssertNil(RapidCrashDetector.detect(symbol: "STALE", bars: stale, nowEpochSeconds: now))
    }

    private func prices(
        _ symbol: String, endingAt end: Int64, _ closes: [Double],
        volume: Double = 1_000, status: VolumeStatus = .reported
    ) -> [MinuteBar] {
        closes.enumerated().map { index, close in
            bar(symbol, end - Int64(closes.count - 1 - index) * 60, close,
                volume: volume, status: status)
        }
    }

    private func bar(
        _ symbol: String, _ epoch: Int64, _ close: Double,
        volume: Double = 1_000, status: VolumeStatus = .reported
    ) -> MinuteBar {
        MinuteBar(symbol: symbol, minuteEpochSeconds: epoch,
                  open: close, high: close, low: close, close: close,
                  volume: volume, volumeStatus: status)
    }
}
