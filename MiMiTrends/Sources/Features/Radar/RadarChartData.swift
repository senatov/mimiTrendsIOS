import Foundation

enum RadarChartRange: String, CaseIterable, Identifiable {
    case oneHour
    case threeHours
    case oneDay
    case oneWeek
    case oneYear
    case latest
    case trades

    var id: Self { self }

    var title: String {
        switch self {
        case .oneHour: "1H"
        case .threeHours: "3H"
        case .oneDay: "1D"
        case .oneWeek: "1W"
        case .oneYear: "1Y"
        case .latest: "Latest"
        case .trades: "Trades"
        }
    }

    var seconds: Int64? {
        switch self {
        case .oneHour: 3_600
        case .threeHours: 10_800
        case .oneDay: 86_400
        case .oneWeek: 7 * 86_400
        case .oneYear: 365 * 86_400
        case .latest, .trades: nil
        }
    }

    var usesDailyBars: Bool { self == .oneWeek || self == .oneYear }
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
    let range: RadarChartRange
    let bars: [MinuteBar]
    let fastEMA: [RadarChartPoint]
    let slowEMA: [RadarChartPoint]
    let trend30: [RadarChartPoint]

    init(
        allBars: [MinuteBar], range: RadarChartRange,
        nowEpochSeconds: Int64, latestLimit: Int = 60,
        focusEpochSeconds: Int64? = nil
    ) {
        self.range = range
        let ranged: [MinuteBar]
        if range == .trades {
            ranged = allBars
        } else if let seconds = range.seconds {
            ranged = allBars.filter { $0.minuteEpochSeconds >= nowEpochSeconds - seconds }
        } else {
            ranged = Array(allBars.suffix(latestLimit))
        }
        let selected: [MinuteBar]
        if let focusEpochSeconds,
           let focusIndex = ranged.indices.min(by: {
               abs(ranged[$0].minuteEpochSeconds - focusEpochSeconds) <
                   abs(ranged[$1].minuteEpochSeconds - focusEpochSeconds)
           }), abs(ranged[focusIndex].minuteEpochSeconds - focusEpochSeconds) <= 90 {
            selected = Array(ranged[max(0, focusIndex - 12)...min(ranged.count - 1, focusIndex + 60)])
        } else {
            selected = ranged
        }
        bars = selected
        let gapLimit: Int64 = range.usesDailyBars ? 4 * 86_400 : 60
        fastEMA = Self.ema(
            allBars, visibleFrom: selected.first?.minuteEpochSeconds, visibleThrough: selected.last?.minuteEpochSeconds,
            period: 9, gapLimit: gapLimit
        )
        slowEMA = Self.ema(
            allBars, visibleFrom: selected.first?.minuteEpochSeconds, visibleThrough: selected.last?.minuteEpochSeconds,
            period: 21, gapLimit: gapLimit
        )
        trend30 = Self.regressionLine(selected.suffix(30))
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
        _ bars: [MinuteBar], visibleFrom: Int64?, visibleThrough: Int64?, period: Int, gapLimit: Int64
    ) -> [RadarChartPoint] {
        guard let visibleFrom, let visibleThrough, let first = bars.first else { return [] }
        let smoothing = 2.0 / Double(period + 1)
        var value = first.close
        var previousMinute: Int64?
        var segment = 0
        var points: [RadarChartPoint] = []
        for bar in bars {
            if let previousMinute, bar.minuteEpochSeconds - previousMinute > gapLimit {
                segment += 1
            }
            if previousMinute != nil {
                value = bar.close * smoothing + value * (1 - smoothing)
            }
            if bar.minuteEpochSeconds >= visibleFrom && bar.minuteEpochSeconds <= visibleThrough {
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

    private static func regressionLine<S: Collection>(_ bars: S) -> [RadarChartPoint] where S.Element == MinuteBar {
        let values = Array(bars)
        guard values.count >= 2 else { return [] }
        let count = Double(values.count)
        let meanX = (count - 1) / 2
        let meanY = values.map(\.close).reduce(0, +) / count
        let numerator = values.enumerated().reduce(0.0) { $0 + (Double($1.offset) - meanX) * ($1.element.close - meanY) }
        let denominator = values.indices.reduce(0.0) { $0 + pow(Double($1) - meanX, 2) }
        guard denominator > 0 else { return [] }
        let slope = numerator / denominator
        return [0, values.count - 1].map { index in
            RadarChartPoint(
                minuteEpochSeconds: values[index].minuteEpochSeconds,
                value: meanY + slope * (Double(index) - meanX),
                segment: 0
            )
        }
    }
}
