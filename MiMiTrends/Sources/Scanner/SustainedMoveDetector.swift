struct SmoothRiseSettings: Sendable {
    var movePercent = RadarScanThresholdDefaults.smoothRisePercent
    var windowMinutes: Int64 = Int64(RadarScanThresholdDefaults.smoothRiseWindowMinutes)
    var maximumPullbackPercent = RadarScanThresholdDefaults.smoothRiseMaximumPullbackPercent
    var minimumTurnover = 50_000_000.0
    var minimumPrice = 5.0
}

enum SmoothRiseDetector {
    private static let sampleInterval = 5
    private static let maximumSampleRisePercent = 0.75
    private static let minimumRisingSampleRatio = 0.60

    static func detect(
        symbol: String,
        bars: [MinuteBar],
        nowEpochSeconds: Int64,
        settings: SmoothRiseSettings = SmoothRiseSettings(),
        dataStatus: String? = nil
    ) -> ScanResult? {
        let recent = bars.filter {
            $0.minuteEpochSeconds >= nowEpochSeconds - settings.windowMinutes * 60 &&
                $0.minuteEpochSeconds <= nowEpochSeconds
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let end = recent.last,
              end.minuteEpochSeconds >= nowEpochSeconds - 600,
              end.close >= settings.minimumPrice,
              recent.count >= 20 else { return nil }

        let reported = recent.filter { $0.volumeStatus == .reported && $0.volume > 0 }
        guard reported.count >= 15,
              reported.reduce(0, { $0 + $1.close * $1.volume }) >= settings.minimumTurnover else {
            return nil
        }

        let anchors = recent.dropLast(19).filter {
            end.minuteEpochSeconds - $0.minuteEpochSeconds >= 1_200
        }
        guard let low = anchors.min(by: { $0.close < $1.close }) else { return nil }
        let change = (end.close / low.close - 1) * 100
        guard change >= settings.movePercent else { return nil }

        let eventBars = recent.filter { $0.minuteEpochSeconds >= low.minuteEpochSeconds }
        guard eventBars.count >= 20,
              !zip(eventBars, eventBars.dropFirst()).contains(where: {
                  $0.1.minuteEpochSeconds - $0.0.minuteEpochSeconds > 300
              }), isSmoothRise(eventBars, maximumPullbackPercent: settings.maximumPullbackPercent) else {
            return nil
        }

        return MarketSignalFactory.make(
            symbol: symbol, bars: recent, start: low, end: end,
            eventBarCount: eventBars.count, changePercent: change,
            source: "Smooth rise",
            displayPrice: end.close, nowEpochSeconds: nowEpochSeconds,
            anomalyScore: 90, dataStatus: dataStatus
        )
    }

    private static func isSmoothRise(
        _ bars: [MinuteBar], maximumPullbackPercent: Double
    ) -> Bool {
        var peak = bars[0].close
        var maximumPullback = 0.0
        for bar in bars {
            peak = max(peak, bar.close)
            maximumPullback = max(maximumPullback, (peak / bar.close - 1) * 100)
        }
        guard maximumPullback <= maximumPullbackPercent else { return false }

        var samples = stride(from: 0, to: bars.count, by: sampleInterval).map { bars[$0].close }
        if (bars.count - 1) % sampleInterval != 0, let last = bars.last {
            samples.append(last.close)
        }
        guard samples.count > 1 else { return false }
        let changes = zip(samples, samples.dropFirst()).map { ($1 / $0 - 1) * 100 }
        let risingRatio = Double(changes.filter { $0 >= 0.01 }.count) / Double(changes.count)
        let largestRise = changes.max() ?? 0
        return risingRatio >= minimumRisingSampleRatio && largestRise <= maximumSampleRisePercent
    }
}
