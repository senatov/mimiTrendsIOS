import Foundation

/// Only completed, fresh candles from one trading session can confirm a movement.
enum YahooCandleSignalPipeline {
    static let currentStatus = "YAHOO_CANDLES"
    static let delayedStatus = "YAHOO_CANDLES_DELAYED"
    static let volumeValidatedStatus = "YAHOO_CANDLES_VOLUME_VALIDATED"
    static let delayedVolumeValidatedStatus = "YAHOO_CANDLES_DELAYED_VOLUME_VALIDATED"

    static func detect(symbol: String, bars: [MinuteBar], nowEpochSeconds: Int64,
                       settings: RadarScanPreferences, volumeValidated: Bool = false) -> ScanResult? {
        let german = MarketCandidateFilter.isGermanSymbol(symbol)
        let market: RadarTradingMarket = german ? .germany : .unitedStates
        let observed = Date(timeIntervalSince1970: Double(nowEpochSeconds))
        guard market.phase(at: observed).isTrading else { return nil }
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowEpochSeconds)
        let evaluationDate = Date(timeIntervalSince1970: Double(evaluationTime))
        guard let sessionStart = market.sessionStart(at: evaluationDate) else { return nil }
        let start = Int64(sessionStart.timeIntervalSince1970)
        let usOpening = !german && market.phase(at: evaluationDate) == .regular &&
            evaluationTime < start + 600
        // Keep the last premarket prices as context for an opening drop. The
        // opening bars themselves still need reported trade volume.
        let contextStart = usOpening ? start - 300 : start
        let completed = bars.filter {
            $0.symbol == symbol && $0.isValid && $0.minuteEpochSeconds >= contextStart
                && $0.minuteEpochSeconds + 60 <= evaluationTime
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        let status = volumeValidated
            ? (german ? delayedVolumeValidatedStatus : volumeValidatedStatus)
            : (german ? delayedStatus : currentStatus)
        let regularStart = market.regularOpen(at: evaluationDate)
            .map { Int64($0.timeIntervalSince1970) }
        let multiHourBars = regularStart.map { opening in
            bars.filter {
                $0.symbol == symbol && $0.isValid &&
                    $0.minuteEpochSeconds >= opening && $0.minuteEpochSeconds + 60 <= evaluationTime
            }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        } ?? []
        let multiHourSignal = regularStart.flatMap { opening in
            hasValidatedVolume(multiHourBars, regularStart: opening, usOpening: false,
                               required: volumeValidated)
                ? MultiHourRiseDetector.detect(symbol: symbol, bars: multiHourBars,
                    nowEpochSeconds: evaluationTime, dataStatus: status,
                    observedAtEpochSeconds: nowEpochSeconds) : nil
        }
        guard let last = completed.last, last.minuteEpochSeconds >= evaluationTime - 180 else {
            return multiHourSignal
        }
        // A short drop can recover before this symbol's next scan. Inspect the
        // last few completed endpoints, retaining the original event time.
        for index in completed.indices.reversed() {
            let end = completed[index]
            guard evaluationTime - end.minuteEpochSeconds <= 180 else { break }
            let candidateBars = Array(completed[...index])
            guard hasValidatedVolume(candidateBars, regularStart: start, usOpening: usOpening,
                                     required: volumeValidated) else { continue }
            if let crash = RapidCrashDetector.detect(symbol: symbol, bars: candidateBars,
                nowEpochSeconds: evaluationTime, settings: settings.rapidCrash,
                dataStatus: status, observedAtEpochSeconds: nowEpochSeconds),
                last.close < crash.signalPrice {
                return crash
            }
        }
        guard hasValidatedVolume(completed, regularStart: start, usOpening: usOpening,
                                 required: volumeValidated) else { return multiHourSignal }
        return multiHourSignal
            ?? RapidRiseDetector.detect(symbol: symbol, bars: completed,
            nowEpochSeconds: evaluationTime, settings: settings.rapidRise,
            dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
            ?? SmoothRiseDetector.detect(symbol: symbol, bars: completed,
                nowEpochSeconds: evaluationTime, settings: settings.smoothRise,
                dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
    }

    private static func hasValidatedVolume(_ bars: [MinuteBar], regularStart: Int64,
                                           usOpening: Bool, required: Bool) -> Bool {
        guard required else { return true }
        guard let end = bars.last else { return false }
        let opening = usOpening && end.minuteEpochSeconds == regularStart + 60
        let recent = Array(bars.suffix(opening ? 2 : 3))
        return recent.count == (opening ? 2 : 3) &&
            recent.allSatisfy { $0.minuteEpochSeconds >= regularStart &&
                $0.volumeStatus == .reported && $0.volume > 0 } &&
            !zip(recent, recent.dropFirst()).contains { pair in
                pair.1.minuteEpochSeconds - pair.0.minuteEpochSeconds > 120
            }
    }
}
