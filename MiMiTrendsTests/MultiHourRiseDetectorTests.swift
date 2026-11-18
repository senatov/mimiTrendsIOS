import XCTest
@testable import MiMiTrends

final class MultiHourRiseDetectorTests: XCTestCase {
    func testCueLikeRiseIsDetectedAndDisplayedForItsFullDuration() throws {
        let opening = Int64(ISO8601DateFormatter().date(
            from: "2026-11-18T14:30:00Z")!.timeIntervalSince1970)
        let bars = makeBars("CUE", start: opening, count: 181, volume: 40_000) {
            3.20 + Double($0) * 0.005
        }
        let now = opening + 181 * 60
        let signal = try XCTUnwrap(YahooCandleSignalPipeline.detect(
            symbol: "CUE", bars: bars, nowEpochSeconds: now,
            settings: RadarScanPreferences(), volumeValidated: true))

        XCTAssertEqual(signal.signalSource, MultiHourRiseDetector.source)
        XCTAssertEqual(signal.signalWindowLabel, "180m")
        XCTAssertGreaterThan(signal.windowChangePercent, 25)
        XCTAssertEqual(signal.dataStatus, YahooCandleSignalPipeline.volumeValidatedStatus)
        XCTAssertEqual(RadarSignalSelection.displayHistory([signal], since: 0, limit: 10)
            .map(\.symbol), ["CUE"])
    }

    func testGermanRiseUsesLocalTurnoverFloor() throws {
        let bars = makeBars("CA1.DE", start: 60_000, count: 121, volume: 300) {
            20 + Double($0) * 0.02
        }
        let signal = try XCTUnwrap(MultiHourRiseDetector.detect(
            symbol: "CA1.DE", bars: bars, nowEpochSeconds: 60_000 + 120 * 60))
        XCTAssertEqual(signal.signalSource, MultiHourRiseDetector.source)
        XCTAssertEqual(signal.priceCurrency, "EUR")
    }

    func testRegularSessionRiseCanStillBeConfirmedJustAfterClose() throws {
        let opening = Int64(ISO8601DateFormatter().date(
            from: "2026-11-18T14:30:00Z")!.timeIntervalSince1970)
        let bars = makeBars("CUE", start: opening, count: 395, volume: 40_000) {
            3.20 + Double($0) * 0.005
        }
        let signal = try XCTUnwrap(YahooCandleSignalPipeline.detect(
            symbol: "CUE", bars: bars, nowEpochSeconds: opening + 395 * 60,
            settings: RadarScanPreferences(), volumeValidated: true))
        XCTAssertEqual(signal.signalSource, MultiHourRiseDetector.source)
        XCTAssertGreaterThanOrEqual(Int(signal.signalWindowLabel.dropLast()) ?? 0, 300)
    }

    func testStrongRiseSurvivesModerateLatePullback() {
        let bars = makeBars("CUE", start: 60_000, count: 181, volume: 40_000) { minute in
            let trend = 3.20 + Double(minute) * 0.006
            return minute >= 160 ? trend * 0.91 : trend
        }
        let signal = MultiHourRiseDetector.detect(
            symbol: "CUE", bars: bars, nowEpochSeconds: 60_000 + 180 * 60)
        XCTAssertNotNil(signal)
    }

    func testRejectsThinSuddenAndReversedMoves() {
        let start: Int64 = 60_000
        let thin = makeBars("CUE", start: start, count: 181, volume: 100) {
            3.20 + Double($0) * 0.005
        }
        let spike = makeBars("CUE", start: start, count: 181, volume: 40_000) {
            $0 < 170 ? 3.20 : 4.10
        }
        let reversed = makeBars("CUE", start: start, count: 181, volume: 40_000) {
            $0 < 150 ? 3.20 + Double($0) * 0.006 : 3.55
        }
        let now = start + 180 * 60
        XCTAssertNil(MultiHourRiseDetector.detect(symbol: "CUE", bars: thin, nowEpochSeconds: now))
        XCTAssertNil(MultiHourRiseDetector.detect(symbol: "CUE", bars: spike, nowEpochSeconds: now))
        XCTAssertNil(MultiHourRiseDetector.detect(symbol: "CUE", bars: reversed, nowEpochSeconds: now))
    }

    private func makeBars(_ symbol: String, start: Int64, count: Int, volume: Double,
                          close: (Int) -> Double) -> [MinuteBar] {
        (0..<count).map { minute in
            let price = close(minute)
            return MinuteBar(symbol: symbol, minuteEpochSeconds: start + Int64(minute) * 60,
                             open: price, high: price, low: price, close: price,
                             volume: volume)
        }
    }
}
