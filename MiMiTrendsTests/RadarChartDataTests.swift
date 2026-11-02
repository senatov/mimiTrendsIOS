import XCTest
@testable import MiMiTrends

final class RadarChartDataTests: XCTestCase {
    func testEMAUsesDesktopSeedAndSmoothing() {
        let bars = [10.0, 12.0, 14.0].enumerated().map { index, close in
            bar(minute: Int64(index + 1), close: close)
        }
        let data = RadarChartData(allBars: bars, range: .latest, nowEpochSeconds: 10_000)

        for (actual, expected) in zip(data.fastEMA.map(\.value), [10, 10.4, 11.12]) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
        let slowExpected = [10, 10 + 2.0 / 11.0, 10 + 6.0 / 11.0 - 2.0 / 121.0]
        for (actual, expected) in zip(data.slowEMA.map(\.value), slowExpected) {
            XCTAssertEqual(actual, expected, accuracy: 0.0001)
        }
    }

    func testLatestShowsOnlySixtyBarsButEMAUsesEarlierHistory() {
        let bars = (1...80).map { bar(minute: Int64($0), close: Double($0)) }
        let data = RadarChartData(allBars: bars, range: .latest, nowEpochSeconds: 10_000)

        XCTAssertEqual(data.bars.count, 60)
        XCTAssertEqual(data.bars.first?.minuteEpochSeconds, 21 * 60)
        XCTAssertEqual(data.fastEMA.first?.minuteEpochSeconds, 21 * 60)
        XCTAssertGreaterThan(data.fastEMA.first?.value ?? 0, 1)

        let fullChart = RadarChartData(
            allBars: bars, range: .latest,
            nowEpochSeconds: 10_000, latestLimit: 360
        )
        XCTAssertEqual(fullChart.bars.count, 80)
    }

    func testRecentRangeAndGapSegments() {
        let bars = [bar(minute: 1, close: 10), bar(minute: 2, close: 12),
                    bar(minute: 5, close: 14)]
        let data = RadarChartData(allBars: bars, range: .oneHour, nowEpochSeconds: 5 * 60)

        XCTAssertEqual(data.bars.count, 3)
        XCTAssertEqual(data.fastEMA.map(\.segment), [0, 0, 1])

        let old = RadarChartData(allBars: bars, range: .oneHour, nowEpochSeconds: 100 * 60)
        XCTAssertTrue(old.bars.isEmpty)
        XCTAssertTrue(old.fastEMA.isEmpty)
    }

    func testNearestBarSnapsCursorToActualCandle() {
        let bars = [bar(minute: 1, close: 10), bar(minute: 3, close: 12)]
        let selected = RadarChartData.nearestBar(
            to: Date(timeIntervalSince1970: 170), in: bars
        )

        XCTAssertEqual(selected?.minuteEpochSeconds, 180)
        XCTAssertNil(RadarChartData.nearestBar(to: Date(), in: []))
    }

    private func bar(minute: Int64, close: Double) -> MinuteBar {
        MinuteBar(
            symbol: "TEST", minuteEpochSeconds: minute * 60,
            open: close, high: close, low: close, close: close,
            volume: 1
        )
    }
}
