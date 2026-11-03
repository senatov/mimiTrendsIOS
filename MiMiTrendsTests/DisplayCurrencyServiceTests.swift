import Foundation
import XCTest
@testable import MiMiTrends

final class DisplayCurrencyServiceTests: XCTestCase {
    func testECBXMLAndCrossConversion() throws {
        let xml = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <gesmes:Envelope xmlns:gesmes="http://www.gesmes.org/xml/2002-08-01">
          <Cube><Cube time='2026-11-03'>
            <Cube currency='USD' rate='1.12'/>
            <Cube currency='GBP' rate='0.84'/>
          </Cube></Cube>
        </gesmes:Envelope>
        """.utf8)
        let rates = try DisplayCurrencyService.decode(xml, fetchedAt: .now)
        XCTAssertEqual(rates.date, "2026-11-03")
        XCTAssertEqual(rates.convert(112, from: "USD", to: "EUR") ?? 0, 100, accuracy: 0.0001)
        XCTAssertEqual(rates.convert(112, from: "USD", to: "GBP") ?? 0, 84, accuracy: 0.0001)
        XCTAssertNil(rates.convert(112, from: "USD", to: "XYZ"))
    }

    func testIPCountryAndCurrencyPayload() throws {
        let response = try JSONDecoder().decode(IPLocationCurrency.self,
            from: Data(#"{"success":true,"country_code":"DE","currency_code":"EUR"}"#.utf8))
        XCTAssertEqual(response.countryCode, "DE")
        XCTAssertEqual(response.currencyCode, "EUR")
    }

    func testChartCandlePricesConvertAndVolumeDoesNot() throws {
        let rates = DisplayCurrencyRates(date: "2026-11-03", ratesPerEuro: ["EUR": 1, "USD": 2],
                                         fetchedAt: .now)
        let bar = MinuteBar(symbol: "AAPL", minuteEpochSeconds: 1_800_000_000,
                            open: 100, high: 110, low: 90, close: 105, volume: 500)
        let converted = try XCTUnwrap(RadarChartCurrency.bars([bar], from: "USD", to: "EUR", rates: rates)?.first)
        XCTAssertEqual(converted.open, 50)
        XCTAssertEqual(converted.close, 52.5)
        XCTAssertEqual(converted.volume, 500)
        XCTAssertNil(RadarChartCurrency.bars([bar], from: "USD", to: "GBP", rates: rates))
    }
}
