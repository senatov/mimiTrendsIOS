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

    func testPositionCrossingWindowAnchorsToVisibleCandleNotHistoricalPrice() async throws {
        let bars = [MinuteBar(symbol: "SAMPLE", minuteEpochSeconds: 600,
                              open: 101, high: 103, low: 100, close: 102, volume: 1_000)]
        let trade = BrokerTradePosition(id: "older", symbol: "SAMPLE", quantity: 10,
            entryEpochSeconds: 60, entryPrice: 50, exitEpochSeconds: nil,
            exitPrice: nil, profitAmount: nil, profitPercent: nil, currency: "EUR")
        let anchor = try XCTUnwrap(RadarTradeVisibleAnchor.point(trade: trade, bars: bars))
        XCTAssertEqual(anchor.epoch, 600)
        XCTAssertEqual(anchor.price, 102)
        let railHeight = await MainActor.run {
            RadarTradeCardOverlay.railHeight(count: 2, width: 900)
        }
        XCTAssertGreaterThan(railHeight, 72)
    }

    func testRecentPurchasesIncludeClosedTradesAndRankRepeatedTradingAboveNewerOneOff() throws {
        let clock = ISO8601DateFormatter()
        let now = try XCTUnwrap(clock.date(from: "2026-11-27T12:00:00Z"))
        func trade(_ date: String, _ type: String, _ isin: String) throws -> BrokerTradeExecution {
            let timestamp = try XCTUnwrap(clock.date(from: date))
            let epoch = Int64(timestamp.timeIntervalSince1970)
            return BrokerTradeExecution(id: epoch, occurredAtEpochSeconds: epoch, description: isin,
                type: type, isin: isin, shares: 1, price: 10, amount: 10, fee: 0, tax: 0, currency: "EUR")
        }
        let executions = try [
            trade("2026-07-26T21:59:59Z", "Buy", "Expired"),
            trade("2026-07-26T22:00:00Z", "Buy", "Regular"),
            trade("2026-08-03T12:00:00Z", "Sell", "Regular"),
            trade("2026-08-10T12:00:00Z", "Buy", "Regular"),
            trade("2026-09-03T12:00:00Z", "Sell", "Regular"),
            trade("2026-09-04T12:00:00Z", "Buy", "Regular"),
            trade("2026-09-04T13:00:00Z", "Sell", "Regular"),
            trade("2026-11-25T12:00:00Z", "Buy", "One-off"),
            trade("2026-11-25T13:00:00Z", "Sell", "One-off"),
            trade("2026-11-26T12:00:00Z", "Sell", "Sale only"),
            trade("2026-11-27T12:00:01Z", "Buy", "Future")
        ]
        let entries = TradeHistoryWatchlist.entries(from: executions, symbols: ["Regular": "AAPL"], now: now)
        XCTAssertEqual(entries.map(\.id), ["Regular", "One-off"])
        XCTAssertEqual(entries.map(\.isPriority), [true, false])
        XCTAssertEqual(entries.map(\.tradingDays), [5, 1])
        XCTAssertEqual(entries.first?.radarSymbol, "AAPL")
        XCTAssertNil(entries.last?.radarSymbol)
    }

    private func execution(id: Int64, time: Int64, type: String, shares: Double, price: Double) -> BrokerTradeExecution {
        BrokerTradeExecution(id: id, occurredAtEpochSeconds: time, description: "Sample", type: type,
            isin: nil, shares: shares, price: price, amount: shares * price, fee: 0, tax: 0, currency: "EUR")
    }
}
