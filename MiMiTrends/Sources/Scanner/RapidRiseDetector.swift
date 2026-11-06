struct RapidRiseSettings: Sendable {
    var risePercent = RadarScanThresholdDefaults.sharpReboundPercent
    var riseWindowMinutes: Int64 = 5
    var minimumPrice = 5.0
    var minimumTurnover = 250_000.0
}

enum RapidRiseDetector {
    static func detect(
        symbol: String,
        bars: [MinuteBar],
        nowEpochSeconds: Int64,
        settings: RapidRiseSettings = RapidRiseSettings()
    ) -> ScanResult? {
        let recent = bars.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let latest = recent.last,
              latest.minuteEpochSeconds >= nowEpochSeconds - 600 else { return nil }

        guard latest.volumeStatus == .reported, latest.volume > 0 else { return nil }
        let window = recent.filter {
            $0.minuteEpochSeconds >= latest.minuteEpochSeconds - settings.riseWindowMinutes * 60 &&
                $0.minuteEpochSeconds < latest.minuteEpochSeconds
        }
        guard let start = window.min(by: { $0.close < $1.close }) else { return nil }
        let change = (latest.close / start.close - 1) * 100
        guard change >= settings.risePercent - 1e-9 else { return nil }
        let eventBars = recent.filter {
            $0.minuteEpochSeconds >= start.minuteEpochSeconds &&
                $0.minuteEpochSeconds <= latest.minuteEpochSeconds
        }
        guard hasReliableActivity(recent, eventBars: eventBars, end: latest, settings: settings) else { return nil }
        return MarketSignalFactory.make(
            symbol: symbol, bars: recent, start: start, end: latest,
            eventBarCount: eventBars.count, changePercent: change,
            source: "Sharp rebound", displayPrice: latest.close,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    private static func hasReliableActivity(
        _ bars: [MinuteBar], eventBars: [MinuteBar], end: MinuteBar, settings: RapidRiseSettings
    ) -> Bool {
        guard end.close >= settings.minimumPrice, eventBars.count >= 2,
              !zip(eventBars, eventBars.dropFirst()).contains(where: { pair in
                  pair.1.minuteEpochSeconds - pair.0.minuteEpochSeconds > 180
              }),
              eventBars.filter({ $0.volumeStatus == .reported && $0.volume > 0 }).count >= 2 else {
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
