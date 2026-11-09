import Foundation

enum TradableCorridorDetector {
    static func detect(
        symbol: String, bars: [MinuteBar], nowEpochSeconds: Int64, dataStatus: String? = nil
    ) -> ScanResult? {
        let sorted = bars.filter { $0.close > 0 }.sorted {
            $0.minuteEpochSeconds < $1.minuteEpochSeconds
        }
        guard let latest = sorted.last,
              nowEpochSeconds - latest.minuteEpochSeconds <= 180 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = marketTimeZone(for: symbol)
        let latestDate = Date(timeIntervalSince1970: TimeInterval(latest.minuteEpochSeconds))
        let cutoff = latest.minuteEpochSeconds - 7_200
        let session = sorted.filter {
            $0.minuteEpochSeconds >= cutoff &&
                calendar.isDate(Date(timeIntervalSince1970: TimeInterval($0.minuteEpochSeconds)),
                                inSameDayAs: latestDate)
        }
        guard session.count >= 45 else { return nil }

        let closes = session.map(\.close)
        let lower = quantile(closes, probability: 0.08)
        let upper = quantile(closes, probability: 0.84)
        guard lower > 0, upper > lower else { return nil }
        let widthPercent = (upper / lower - 1) * 100
        guard (0.65...6.0).contains(widthPercent) else { return nil }

        let tolerance = (upper - lower) * 0.12
        let range = (lower - tolerance)...(upper + tolerance)
        guard range.contains(latest.close),
              session.suffix(12).filter({ !range.contains($0.close) }).count <= 1 else {
            return nil
        }
        let lowerRange = (lower - tolerance)...(lower + tolerance)
        let upperRange = (upper - tolerance)...(upper + tolerance)
        let lowerTouches = touchGroups(session) { lowerRange.contains($0.low) }
        let upperTouches = touchGroups(session) { upperRange.contains($0.high) }
        guard lowerTouches >= 2, upperTouches >= 2 else { return nil }
        let contained = Double(session.filter { range.contains($0.close) }.count) / Double(session.count)
        guard contained >= 0.82 else { return nil }

        let halfWidth = (upper - lower) / 2
        let firstAverage = session.prefix(10).reduce(0) { $0 + $1.close } / 10
        let lastAverage = session.suffix(10).reduce(0) { $0 + $1.close } / 10
        guard abs(lastAverage - firstAverage) / halfWidth <= 0.90 else { return nil }

        let position = min(max((latest.close - lower) / (upper - lower), 0), 1)
        let remaining = max((upper - latest.close) / latest.close * 100, 0)
        let edgeScore: Double
        if position <= 0.20 {
            edgeScore = 1
        } else if position <= 0.50 {
            edgeScore = 1 - (position - 0.20) / 0.30 * 0.45
        } else {
            edgeScore = max(1 - position, 0) * 0.70
        }
        let widthScore = min(max((widthPercent - 0.65) / 1.50, 0), 1)
        let repeatability = min(Double(lowerTouches + upperTouches) / 8, 1)
        let score = min(max(Int(((
            0.45 * edgeScore + 0.25 * widthScore + 0.20 * repeatability + 0.10 * contained
        ) * 100).rounded()), 0), 100)
        guard score >= 35, remaining >= 0.25 else { return nil }

        return MarketSignalFactory.make(
            symbol: symbol, bars: sorted, start: latest, end: latest,
            eventBarCount: session.count, changePercent: remaining,
            source: "Tradable corridor", displayPrice: upper,
            nowEpochSeconds: nowEpochSeconds,
            anomalyScore: Double(score), windowLabel: "120m corridor", dataStatus: dataStatus
        )
    }

    private static func marketTimeZone(for symbol: String) -> TimeZone {
        let identifier: String
        if symbol.uppercased().hasSuffix(".HE") {
            identifier = "Europe/Helsinki"
        } else if symbol.contains(".") {
            identifier = "Europe/Berlin"
        } else {
            identifier = "America/New_York"
        }
        return TimeZone(identifier: identifier) ?? .gmt
    }

    private static func quantile(_ values: [Double], probability: Double) -> Double {
        let sorted = values.sorted()
        let position = min(max((Double(sorted.count) + 1.0 / 3) * probability - 2.0 / 3, 0),
                           Double(sorted.count - 1))
        let lowerIndex = Int(position)
        let fraction = position - Double(lowerIndex)
        if lowerIndex + 1 >= sorted.count { return sorted[lowerIndex] }
        return sorted[lowerIndex] + (sorted[lowerIndex + 1] - sorted[lowerIndex]) * fraction
    }

    private static func touchGroups(
        _ bars: [MinuteBar], matching: (MinuteBar) -> Bool
    ) -> Int {
        var groups = 0
        var touching = false
        for bar in bars {
            let current = matching(bar)
            if current && !touching { groups += 1 }
            touching = current
        }
        return groups
    }
}
