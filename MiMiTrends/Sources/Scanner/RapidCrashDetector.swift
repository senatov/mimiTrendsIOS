struct RapidCrashSettings: Sendable {
    var crashPercent = RadarScanThresholdDefaults.shortDropPercent
    var crashWindowMinutes: Int64 = 5
    var sustainedCrashPercent = RadarScanThresholdDefaults.sustainedDropPercent
    var sustainedCrashWindowMinutes: Int64 = 15
    var minimumPrice = 5.0
    var minimumTurnover = 250_000.0
}

enum RapidCrashDetector {
    static func detect(
        symbol: String,
        bars: [MinuteBar],
        nowEpochSeconds: Int64,
        settings: RapidCrashSettings = RapidCrashSettings()
    ) -> ScanResult? {
        let recent = bars.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let latest = recent.last, recent.count >= 2,
              latest.close < recent[recent.count - 2].close,
              latest.minuteEpochSeconds >= nowEpochSeconds - 600 else { return nil }

        // Use the newest available bar as the event end; otherwise a recovered
        // drop in the trailing window can be presented as the current signal.
        let latestCandidates = [
            crashEndingAt(latest, bars: recent, settings: settings,
                          windowMinutes: settings.crashWindowMinutes,
                          minimumDropPercent: settings.crashPercent, anchorAtPeak: true),
            crashEndingAt(latest, bars: recent, settings: settings,
                          windowMinutes: settings.sustainedCrashWindowMinutes,
                          minimumDropPercent: settings.sustainedCrashPercent, anchorAtPeak: true)
        ].compactMap { $0 }
        guard let move = latestCandidates.min(by: { $0.change < $1.change }) else { return nil }
        return MarketSignalFactory.make(
            symbol: symbol, bars: recent, start: move.start, end: move.end,
            eventBarCount: move.count, changePercent: move.change,
            source: "Rapid crash", displayPrice: move.end.close,
            nowEpochSeconds: nowEpochSeconds
        )
    }

    private static func crashEndingAt(
        _ end: MinuteBar,
        bars: [MinuteBar],
        settings: RapidCrashSettings,
        windowMinutes: Int64,
        minimumDropPercent: Double,
        anchorAtPeak: Bool
    ) -> Candidate? {
        let window = bars.filter {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - windowMinutes * 60 &&
                $0.minuteEpochSeconds <= end.minuteEpochSeconds
        }
        let start = anchorAtPeak ? window.max(by: { $0.close < $1.close }) : window.first
        guard let start,
              (end.minuteEpochSeconds - start.minuteEpochSeconds) / 60 >= 1,
              start.close > 0, end.close > 0 else { return nil }
        let change = (end.close / start.close - 1) * 100
        guard change <= -minimumDropPercent + 1e-9 else { return nil }
        if anchorAtPeak &&
            (end.minuteEpochSeconds - start.minuteEpochSeconds) / 60 > settings.crashWindowMinutes &&
            !hasAcceleratingDrop(window, start: start, end: end, rapidWindowMinutes: settings.crashWindowMinutes) {
            return nil
        }
        let precedingLow = bars.filter {
            $0.minuteEpochSeconds >= start.minuteEpochSeconds - settings.sustainedCrashWindowMinutes * 60 &&
                $0.minuteEpochSeconds < start.minuteEpochSeconds && $0.close > 0
        }.map(\.close).min()
        if windowMinutes > settings.crashWindowMinutes, let precedingLow, end.close >= precedingLow { return nil }
        let eventBars = window.filter { $0.minuteEpochSeconds >= start.minuteEpochSeconds }
        guard hasReliableActivity(bars, eventBars: eventBars, end: end, settings: settings) else { return nil }
        return Candidate(start: start, end: end, change: change, count: eventBars.count)
    }

    private static func hasAcceleratingDrop(
        _ window: [MinuteBar], start: MinuteBar, end: MinuteBar, rapidWindowMinutes: Int64
    ) -> Bool {
        guard let recentStart = window.last(where: {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - rapidWindowMinutes * 60 &&
                $0.minuteEpochSeconds <= end.minuteEpochSeconds - 180
        }) else { return false }
        let earlierMinutes = Double(recentStart.minuteEpochSeconds - start.minuteEpochSeconds) / 60
        let recentMinutes = Double(end.minuteEpochSeconds - recentStart.minuteEpochSeconds) / 60
        guard earlierMinutes >= 3, recentMinutes > 0 else { return false }
        let recentRate = -(end.close / recentStart.close - 1) * 100 / recentMinutes
        let earlierRate = -(recentStart.close / start.close - 1) * 100 / earlierMinutes
        return recentRate >= 0.05 && recentRate >= max(earlierRate, 0) * 1.5
    }

    private static func hasReliableActivity(
        _ bars: [MinuteBar], eventBars: [MinuteBar], end: MinuteBar, settings: RapidCrashSettings
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

    private struct Candidate {
        let start: MinuteBar
        let end: MinuteBar
        let change: Double
        let count: Int
    }
}
