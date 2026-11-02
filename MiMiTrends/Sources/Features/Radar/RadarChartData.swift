import Foundation

enum RadarChartRange: String, CaseIterable, Identifiable {
    case oneHour
    case threeHours
    case oneDay
    case latest

    var id: Self { self }

    var title: String {
        switch self {
        case .oneHour: "1H"
        case .threeHours: "3H"
        case .oneDay: "1D"
        case .latest: "Latest"
        }
    }

    var seconds: Int64? {
        switch self {
        case .oneHour: 3_600
        case .threeHours: 10_800
        case .oneDay: 86_400
        case .latest: nil
        }
    }
}

struct RadarChartPoint: Identifiable {
    let minuteEpochSeconds: Int64
    let value: Double
    let segment: Int

    var id: Int64 { minuteEpochSeconds }
    var date: Date { Date(timeIntervalSince1970: TimeInterval(minuteEpochSeconds)) }
}

struct RadarChartInspection {
    let bar: MinuteBar
    let price: Double
    let isPinned: Bool
}

struct RadarChartData {
    let bars: [MinuteBar]
    let fastEMA: [RadarChartPoint]
    let slowEMA: [RadarChartPoint]

    init(
        allBars: [MinuteBar], range: RadarChartRange,
        nowEpochSeconds: Int64, latestLimit: Int = 60
    ) {
        let selected: [MinuteBar]
        if let seconds = range.seconds {
            selected = allBars.filter { $0.minuteEpochSeconds >= nowEpochSeconds - seconds }
        } else {
            selected = Array(allBars.suffix(latestLimit))
        }
        bars = selected
        fastEMA = Self.ema(allBars, visibleFrom: selected.first?.minuteEpochSeconds, period: 9)
        slowEMA = Self.ema(allBars, visibleFrom: selected.first?.minuteEpochSeconds, period: 21)
    }

    static func nearestBar(to date: Date, in bars: [MinuteBar]) -> MinuteBar? {
        let timestamp = date.timeIntervalSince1970
        return bars.min {
            abs(TimeInterval($0.minuteEpochSeconds) - timestamp) <
                abs(TimeInterval($1.minuteEpochSeconds) - timestamp)
        }
    }

    // Match the desktop TrendSeriesCalculator seed and smoothing rule.
    private static func ema(
        _ bars: [MinuteBar], visibleFrom: Int64?, period: Int
    ) -> [RadarChartPoint] {
        guard let visibleFrom, let first = bars.first else { return [] }
        let smoothing = 2.0 / Double(period + 1)
        var value = first.close
        var previousMinute: Int64?
        var segment = 0
        var points: [RadarChartPoint] = []
        for bar in bars {
            if let previousMinute, bar.minuteEpochSeconds - previousMinute > 60 {
                segment += 1
            }
            if previousMinute != nil {
                value = bar.close * smoothing + value * (1 - smoothing)
            }
            if bar.minuteEpochSeconds >= visibleFrom {
                points.append(RadarChartPoint(
                    minuteEpochSeconds: bar.minuteEpochSeconds,
                    value: value,
                    segment: segment
                ))
            }
            previousMinute = bar.minuteEpochSeconds
        }
        return points
    }
}
