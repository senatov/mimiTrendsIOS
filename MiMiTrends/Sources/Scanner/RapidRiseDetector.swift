struct RapidRiseSettings: Sendable {
    var risePercent = RadarScanThresholdDefaults.sharpReboundPercent
    var riseWindowMinutes: Int64 = 5
    var minimumPrice = 5.0
    var minimumTurnover = 250_000.0
}

/// A decline into a local low, then a higher low and a break above the intervening high.
/// The breakout is observable only after the local low, never at the low itself.
enum RapidRiseDetector {
    static func detect(
        symbol: String,
        bars: [MinuteBar],
        nowEpochSeconds: Int64,
        settings: RapidRiseSettings = RapidRiseSettings(),
        dataStatus: String? = nil,
        observedAtEpochSeconds: Int64? = nil
    ) -> ScanResult? {
        let recent = bars.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let latest = recent.last, recent.count >= 6,
              latest.volumeStatus == .reported, latest.volume > 0,
              latest.minuteEpochSeconds >= nowEpochSeconds - 600,
              latest.close > recent[recent.count - 2].close else { return nil }

        let lastIndex = recent.count - 1
        let earliestLow = latest.minuteEpochSeconds - settings.riseWindowMinutes * 60
        for lowIndex in (2..<(lastIndex - 2)).reversed() {
            let low = recent[lowIndex]
            if low.minuteEpochSeconds < earliestLow { break }
            guard low.close < recent[lowIndex - 1].close,
                  low.close < recent[lowIndex + 1].close,
                  precedingDecline(in: recent, lowIndex: lowIndex, threshold: settings.risePercent) else {
                continue
            }
            for higherLowIndex in ((lowIndex + 2)..<lastIndex).reversed() {
                let higherLow = recent[higherLowIndex]
                guard higherLow.close > low.close,
                      higherLow.close < recent[higherLowIndex - 1].close,
                      higherLow.close < recent[higherLowIndex + 1].close,
                      recent[(lowIndex + 1)..<higherLowIndex].allSatisfy({ $0.close > low.close }) else {
                    continue
                }
                let interveningHigh = recent[(lowIndex + 1)..<higherLowIndex].map(\.close).max() ?? 0
                guard interveningHigh > higherLow.close,
                      latest.close > interveningHigh,
                      recent[lastIndex - 1].close <= interveningHigh else { continue }
                let change = (latest.close / low.close - 1) * 100
                guard change >= settings.risePercent - 1e-9 else { continue }
                let eventBars = Array(recent[lowIndex...lastIndex])
                guard hasReliableActivity(recent, eventBars: eventBars, end: latest, settings: settings) else {
                    continue
                }
                return MarketSignalFactory.make(
                    symbol: symbol, bars: recent, start: low, end: latest,
                    eventBarCount: eventBars.count, changePercent: change,
                    source: "Confirmed reversal", displayPrice: latest.close,
                    nowEpochSeconds: nowEpochSeconds, dataStatus: dataStatus,
                    observedAtEpochSeconds: observedAtEpochSeconds
                )
            }
        }
        return nil
    }

    private static func precedingDecline(in bars: [MinuteBar], lowIndex: Int, threshold: Double) -> Bool {
        let low = bars[lowIndex]
        let preceding = bars[..<lowIndex].filter {
            $0.minuteEpochSeconds >= low.minuteEpochSeconds - 15 * 60
        }
        guard preceding.count >= 2, let high = preceding.map(\.close).max() else { return false }
        return (low.close / high - 1) * 100 <= -threshold + 1e-9
    }

    private static func hasReliableActivity(
        _ bars: [MinuteBar], eventBars: [MinuteBar], end: MinuteBar, settings: RapidRiseSettings
    ) -> Bool {
        guard end.close >= settings.minimumPrice, eventBars.count >= 4,
              !zip(eventBars, eventBars.dropFirst()).contains(where: { pair in
                  pair.1.minuteEpochSeconds - pair.0.minuteEpochSeconds > 120
              }),
              eventBars.filter({ $0.volumeStatus == .reported && $0.volume > 0 }).count >= 4 else {
            return false
        }
        let active = bars.filter {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - 1_800 &&
                $0.minuteEpochSeconds <= end.minuteEpochSeconds &&
                $0.volumeStatus == .reported && $0.volume > 0
        }
        return active.count >= 3 &&
            active.reduce(0) { $0 + $1.close * $1.volume } >= settings.minimumTurnover
    }
}
