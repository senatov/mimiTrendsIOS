enum MultiHourRiseDetector {
    static let source = "Multi-hour rise"
    private static let windowSeconds: Int64 = 6 * 60 * 60
    private static let minimumDurationSeconds: Int64 = 90 * 60
    private static let sampleSeconds: Int64 = 20 * 60

    static func detect(
        symbol: String, bars: [MinuteBar], nowEpochSeconds: Int64,
        dataStatus: String? = nil, observedAtEpochSeconds: Int64? = nil
    ) -> ScanResult? {
        let german = MarketCandidateFilter.isGermanSymbol(symbol)
        let recent = bars.filter {
            $0.isValid && $0.minuteEpochSeconds >= nowEpochSeconds - windowSeconds &&
                $0.minuteEpochSeconds <= nowEpochSeconds
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let end = recent.last, end.minuteEpochSeconds >= nowEpochSeconds - 180,
              end.close >= 2, recent.count >= 60 else { return nil }
        let anchors = recent.filter {
            end.minuteEpochSeconds - $0.minuteEpochSeconds >= minimumDurationSeconds
        }
        guard let low = anchors.min(by: { $0.close < $1.close }) else { return nil }
        let change = (end.close / low.close - 1) * 100
        guard change >= (german ? 8 : 15) else { return nil }

        let event = recent.filter { $0.minuteEpochSeconds >= low.minuteEpochSeconds }
        guard event.count >= 60,
              !zip(event, event.dropFirst()).contains(where: {
                  $0.1.minuteEpochSeconds - $0.0.minuteEpochSeconds > 300
              }) else { return nil }
        let reported = event.filter { $0.volumeStatus == .reported && $0.volume > 0 }
        let turnover = reported.reduce(0) { $0 + $1.close * $1.volume }
        let lastHourTurnover = reported.filter {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - 3_600
        }.reduce(0) { $0 + $1.close * $1.volume }
        guard reported.count >= 60, turnover >= (german ? 250_000 : 10_000_000),
              lastHourTurnover >= (german ? 50_000 : 1_000_000),
              followsSustainedRise(event) else { return nil }

        return MarketSignalFactory.make(
            symbol: symbol, bars: recent, start: low, end: end,
            eventBarCount: event.count, changePercent: change, source: source,
            displayPrice: end.close, nowEpochSeconds: nowEpochSeconds,
            anomalyScore: 85, dataStatus: dataStatus,
            observedAtEpochSeconds: observedAtEpochSeconds
        )
    }

    private static func followsSustainedRise(_ bars: [MinuteBar]) -> Bool {
        guard let first = bars.first, let end = bars.last else { return false }
        var peak = first.close
        var maximumPullback = 0.0
        for bar in bars {
            peak = max(peak, bar.close)
            maximumPullback = max(maximumPullback, (peak / bar.close - 1) * 100)
        }
        guard maximumPullback <= 12, end.close >= peak * 0.9 else { return false }

        var samples = [first.close]
        var nextSample = first.minuteEpochSeconds + sampleSeconds
        for bar in bars.dropFirst() where bar.minuteEpochSeconds >= nextSample {
            samples.append(bar.close)
            nextSample = bar.minuteEpochSeconds + sampleSeconds
        }
        if bars.last!.minuteEpochSeconds > nextSample - sampleSeconds {
            samples.append(end.close)
        }
        let intervals = zip(samples, samples.dropFirst()).map { $1 / $0 - 1 }
        guard intervals.count >= 4 else { return false }
        let rising = intervals.filter { $0 >= 0.002 }.count
        return rising >= 3 && Double(rising) / Double(intervals.count) >= 0.5
    }
}
