import XCTest
@testable import MiMiTrends

final class RadarListingAndTradeTests: XCTestCase {
    func testFlagsReferToListingNotIssuerCountry() {
        XCTAssertEqual(RadarCompanyMetadata.listingCountry(for: "IREN"), "US")
        XCTAssertEqual(RadarCompanyMetadata.listingCountry(for: "EQT"), "US")
        XCTAssertEqual(RadarCompanyMetadata.listingCountry(for: "ASML.DE"), "DE")
        XCTAssertEqual(RadarCompanyMetadata.listingCountry(for: "AIR.PA"), "FR")
        XCTAssertEqual(RadarCompanyMetadata.listingCountry(for: "LS:43763"), "DE")
        XCTAssertEqual(RadarCompanyMetadata.flag(for: "US"), "🇺🇸")
    }

    func testSeparateOpenPurchasesKeepTheirActualDatesAndPrices() {
        let buys = [execution(id: 1, time: 60, type: "Buy", shares: 10, price: 100),
                    execution(id: 2, time: 120, type: "Buy", shares: 5, price: 110)]
        let positions = BrokerTradeChartMatcher.positions(symbol: "SAMPLE", companyName: "Sample", executions: buys)
        XCTAssertEqual(positions.count, 2)
        XCTAssertEqual(positions.map(\.entryEpochSeconds), [60, 120])
        XCTAssertEqual(positions.map(\.entryPrice), [100, 110])
        XCTAssertEqual(positions.map(\.quantity), [10, 5])
    }

    func testPartialSaleClosesFIFOAndLeavesActualOpenLot() {
        let executions = [execution(id: 1, time: 60, type: "Buy", shares: 10, price: 100),
                          execution(id: 2, time: 120, type: "Buy", shares: 5, price: 110),
                          execution(id: 3, time: 180, type: "Sell", shares: 12, price: 120)]
        let positions = BrokerTradeChartMatcher.positions(symbol: "SAMPLE", companyName: "Sample", executions: executions)
        let closed = positions.filter { $0.exitEpochSeconds != nil }
        XCTAssertEqual(closed.count, 2)
        XCTAssertEqual(closed.map(\.quantity), [10, 2])
        let open = positions.filter { $0.exitEpochSeconds == nil }
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.quantity, 3)
        XCTAssertEqual(open.first?.entryEpochSeconds, 120)
        XCTAssertEqual(open.first?.entryPrice, 110)
    }

    func testPositionCrossingWindowAnchorsToVisibleCandleNotHistoricalPrice() throws {
        let bars = [MinuteBar(symbol: "SAMPLE", minuteEpochSeconds: 600,
                              open: 101, high: 103, low: 100, close: 102, volume: 1_000)]
        let trade = BrokerTradePosition(id: "older", symbol: "SAMPLE", quantity: 10,
            entryEpochSeconds: 60, entryPrice: 50, exitEpochSeconds: nil,
            exitPrice: nil, profitAmount: nil, profitPercent: nil, currency: "EUR")
        let anchor = try XCTUnwrap(RadarTradeVisibleAnchor.point(trade: trade, bars: bars))
        XCTAssertEqual(anchor.epoch, 600)
        XCTAssertEqual(anchor.price, 102)
        XCTAssertGreaterThan(RadarTradeCardOverlay.railHeight(count: 2, width: 900), 72)
    }

    private func execution(id: Int64, time: Int64, type: String, shares: Double, price: Double) -> BrokerTradeExecution {
        BrokerTradeExecution(id: id, occurredAtEpochSeconds: time, description: "Sample", type: type,
            isin: nil, shares: shares, price: price, amount: shares * price, fee: 0, tax: 0, currency: "EUR")
    }
}
