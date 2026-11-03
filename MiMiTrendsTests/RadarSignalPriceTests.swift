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
        let restored = try JSONDecoder().decode(
            ScanResult.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        XCTAssertNil(restored.priceCurrency)
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
