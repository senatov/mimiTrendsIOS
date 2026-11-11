import Foundation

/// Only completed, fresh candles from one trading session can confirm a movement.
enum YahooCandleSignalPipeline {
    static let currentStatus = "YAHOO_CANDLES"
    static let delayedStatus = "YAHOO_CANDLES_DELAYED"
    static let verifiedStatus = "YAHOO_CANDLES_FINNHUB_VERIFIED"

    static func detect(symbol: String, bars: [MinuteBar], nowEpochSeconds: Int64,
                       settings: RadarScanPreferences, verified: Bool = false) -> ScanResult? {
        let german = MarketCandidateFilter.isGermanSymbol(symbol)
        let market: RadarTradingMarket = german ? .germany : .unitedStates
        let observed = Date(timeIntervalSince1970: Double(nowEpochSeconds))
        guard market.phase(at: observed).isTrading else { return nil }
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowEpochSeconds)
        let evaluationDate = Date(timeIntervalSince1970: Double(evaluationTime))
        guard let sessionStart = market.sessionStart(at: evaluationDate) else { return nil }
        let start = Int64(sessionStart.timeIntervalSince1970)
        let completed = bars.filter {
            $0.symbol == symbol && $0.isValid && $0.minuteEpochSeconds >= start
                && $0.minuteEpochSeconds >= nowEpochSeconds - MarketBarStore.retentionSeconds
                && $0.minuteEpochSeconds + 60 <= evaluationTime
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let last = completed.last, last.minuteEpochSeconds >= evaluationTime - 180 else { return nil }
        let status = verified ? verifiedStatus : (german ? delayedStatus : currentStatus)
        return RapidCrashDetector.detect(symbol: symbol, bars: completed,
            nowEpochSeconds: evaluationTime, settings: settings.rapidCrash, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
            ?? RapidRiseDetector.detect(symbol: symbol, bars: completed,
                nowEpochSeconds: evaluationTime, settings: settings.rapidRise, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
            ?? SmoothRiseDetector.detect(symbol: symbol, bars: completed,
                nowEpochSeconds: evaluationTime, settings: settings.smoothRise, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
    }
}
