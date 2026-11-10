import XCTest
@testable import MiMiTrends

final class LSQuoteMoveDetectorTests: XCTestCase {
    func testDropUsesExecutableSidesAndDoesNotInventVolume() throws {
        let rows = quotes()
        var settings = RadarScanPreferences()
        settings.crashPercent = 1.5
        let signal = try XCTUnwrap(LSQuoteMoveDetector.detect(rows, nowMillis: 1_000_000,
                                                            settings: settings))
        XCTAssertEqual(signal.symbol, "LS:123")
        XCTAssertEqual(signal.signalSource, "L&S quote drop")
        XCTAssertEqual(signal.dataStatus, "QUOTE_NO_VOLUME")
        XCTAssertEqual(signal.signalEpochMillis, 1_000_000)
        XCTAssertEqual(signal.windowVolume, 0)
        XCTAssertEqual(signal.sessionTurnover, 0)
        XCTAssertEqual(signal.windowChangePercent, -1.9, accuracy: 0.00001)
    }

    func testStaleGappedAndWideSpreadQuotesDoNotSignal() {
        XCTAssertNil(LSQuoteMoveDetector.detect(quotes(), nowMillis: 1_200_000,
                                               settings: RadarScanPreferences()))
        let gaps = quotes().enumerated().filter { $0.offset % 4 == 0 }.map(\.element)
        XCTAssertNil(LSQuoteMoveDetector.detect(gaps, nowMillis: 1_000_000,
                                               settings: RadarScanPreferences()))
        let wide = quotes().map { LSQuoteObservation(instrumentID: $0.instrumentID,
            observedAtMillis: $0.observedAtMillis, bid: $0.bid, ask: $0.ask + 5) }
        XCTAssertNil(LSQuoteMoveDetector.detect(wide, nowMillis: 1_000_000,
                                               settings: RadarScanPreferences()))
    }

    func testDiagnosticsDistinguishStaleQuotesGapsAndThresholds() {
        let settings = RadarScanPreferences()
        XCTAssertEqual(LSQuoteMoveDetector.evaluate(quotes(), nowMillis: 1_200_000,
                                                   settings: settings).reason, "staleQuote")
        let gaps = quotes().enumerated().filter { [0, 4, 10].contains($0.offset) }.map(\.element)
        XCTAssertEqual(LSQuoteMoveDetector.evaluate(gaps, nowMillis: 1_000_000,
                                                   settings: settings).reason, "quoteGap")
        var highThresholds = settings
        highThresholds.crashPercent = 20
        highThresholds.sustainedCrashPercent = 20
        highThresholds.risePercent = 20
        XCTAssertEqual(LSQuoteMoveDetector.evaluate(quotes(), nowMillis: 1_000_000,
                                                   settings: highThresholds).reason, "belowThreshold")
    }

    private func quotes() -> [LSQuoteObservation] {
        (0...10).map { index in
            LSQuoteObservation(instrumentID: "123", observedAtMillis: 700_000 + Int64(index) * 30_000,
                               bid: 100 - Double(index) * 0.2, ask: 100.1 - Double(index) * 0.2)
        }
    }
}
