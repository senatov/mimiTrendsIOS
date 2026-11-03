import Foundation
import XCTest
@testable import MiMiTrends

final class RadarSignalPriceTests: XCTestCase {
    private let nowSeconds: Int64 = 1_800_000_060

    func testRecentUSDSignalUsesVerifiedFXAndKeepsSourcePriceInExplanation() throws {
        let signal = makeSignal()
        let quote = FMPExchangeRate(eurosToDollars: 1.1194,
                                    observedAtMillis: nowSeconds * 1_000)
        let display = RadarSignalPrice.display(signal, exchangeRate: quote,
                                               nowMillis: nowSeconds * 1_000)
        XCTAssertEqual(display.estimatedEUR ?? 0, 295.2743, accuracy: 0.0001)
        XCTAssertTrue(display.text.contains("€"))
        XCTAssertTrue(display.explanation.contains("USD"))

        let staleDisplay = RadarSignalPrice.display(signal, exchangeRate: quote,
                                                    nowMillis: nowSeconds * 1_000 + 21 * 60_000)
        XCTAssertNil(staleDisplay.estimatedEUR)
        XCTAssertTrue(staleDisplay.text.contains("$"))
    }

    func testFXDecoderRejectsOldQuoteAndWrongSymbol() throws {
        let quote = Data("""
        [{"symbol":"EURUSD","price":1.1194,"timestamp":1800000060}]
        """.utf8)
        XCTAssertEqual(try FMPExchangeRateSource.decode(quote, nowMillis: nowSeconds * 1_000)
            .eurosToDollars, 1.1194)
        XCTAssertThrowsError(try FMPExchangeRateSource.decode(
            quote, nowMillis: nowSeconds * 1_000 + 21 * 60_000
        ))
        XCTAssertThrowsError(try FMPExchangeRateSource.decode(
            Data(#"[{"symbol":"USDEUR","price":0.89,"timestamp":1800000060}]"#.utf8),
            nowMillis: nowSeconds * 1_000
        ))
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
