import Foundation
import XCTest
@testable import MiMiTrends

final class RadarSignalPriceTests: XCTestCase {
    private let nowSeconds: Int64 = 1_800_000_060

    func testDisplayCurrencyConvertsWithoutSignalTimeRestrictionAndNeverShowsSourceUSD() {
        let signal = makeSignal()
        let rates = DisplayCurrencyRates(date: "2026-11-03", ratesPerEuro: ["EUR": 1, "USD": 1.1194, "GBP": 0.84],
                                         fetchedAt: Date())
        let euro = RadarSignalPrice.display(signal, rates: rates, currency: "EUR")
        XCTAssertEqual(euro.convertedAmount ?? 0, 295.2743, accuracy: 0.0001)
        XCTAssertTrue(euro.text.contains("€"))
        XCTAssertFalse(euro.text.contains("$"))
        let pounds = RadarSignalPrice.display(signal, rates: rates, currency: "GBP")
        XCTAssertTrue(pounds.text.contains("£"))
        XCTAssertFalse(pounds.text.contains("$"))
        let waiting = RadarSignalPrice.display(signal, rates: nil, currency: "EUR")
        XCTAssertEqual(waiting.text, "—")
    }

    func testOldSignalPayloadWithoutCurrencyStillDecodes() throws {
        let data = try JSONEncoder().encode(makeSignal())
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        payload.removeValue(forKey: "priceCurrency")
        payload.removeValue(forKey: "anchorCandle")
        payload.removeValue(forKey: "eventCandle")
        payload.removeValue(forKey: "recentTurnover")
        payload.removeValue(forKey: "currentPrice")
        payload.removeValue(forKey: "currentPriceSource")
        payload.removeValue(forKey: "currentPriceAtMillis")
        let restored = try JSONDecoder().decode(
            ScanResult.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertNil(restored.priceCurrency)
        XCTAssertNil(restored.eventCandle)
        XCTAssertNil(restored.recentTurnover)
    }

    func testEventCandleSurvivesSignalSerialization() throws {
        let original = makeSignal()
        let restored = try JSONDecoder().decode(ScanResult.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.anchorCandle?.close, 330)
        XCTAssertEqual(restored.eventCandle?.close, 330.53)
        XCTAssertEqual(restored.eventCandle?.volume, 1_000)
        XCTAssertEqual(restored.recentTurnover, 660_530)
    }

    func testLateDetectionDoesNotCountCandlesAfterEventInWindowVolume() {
        let start = MinuteBar(symbol: "AAPL", minuteEpochSeconds: nowSeconds - 180,
            open: 100, high: 100, low: 100, close: 100, volume: 100)
        let end = MinuteBar(symbol: "AAPL", minuteEpochSeconds: nowSeconds - 120,
            open: 100, high: 100, low: 99, close: 99, volume: 200)
        let later = MinuteBar(symbol: "AAPL", minuteEpochSeconds: nowSeconds - 60,
            open: 99, high: 99, low: 98, close: 98, volume: 10_000)
        let signal = MarketSignalFactory.make(symbol: "AAPL", bars: [start, end, later],
            start: start, end: end, eventBarCount: 2, changePercent: -1,
            source: "Rapid crash", displayPrice: 99, nowEpochSeconds: nowSeconds)
        XCTAssertEqual(signal.windowVolume, 300)
        XCTAssertEqual(signal.sessionVolume, 300)
        XCTAssertEqual(signal.recentTurnover, 29_800)
        XCTAssertEqual(signal.eventCandle, end)
    }

    private func makeSignal() -> ScanResult {
        let start = MinuteBar(symbol: "AAPL", minuteEpochSeconds: nowSeconds - 60,
                              open: 330.0, high: 330.1, low: 329.9, close: 330.0, volume: 1_000)
        let end = MinuteBar(symbol: "AAPL", minuteEpochSeconds: nowSeconds,
                            open: 330.0, high: 330.6, low: 329.9, close: 330.53, volume: 1_000)
        return MarketSignalFactory.make(
            symbol: "AAPL", bars: [start, end], start: start, end: end,
            eventBarCount: 2, changePercent: 0.16, source: "Sustained rise",
            displayPrice: end.close, nowEpochSeconds: nowSeconds
        )
    }
}
