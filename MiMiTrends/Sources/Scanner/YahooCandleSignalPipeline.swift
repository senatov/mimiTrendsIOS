import Foundation

/// Only completed, fresh candles from one trading session can confirm a movement.
enum YahooCandleSignalPipeline {
    static let currentStatus = "YAHOO_CANDLES"
    static let delayedStatus = "YAHOO_CANDLES_DELAYED"

    static func detect(symbol: String, bars: [MinuteBar], nowEpochSeconds: Int64,
                       settings: RadarScanPreferences) -> ScanResult? {
        let german = MarketCandidateFilter.isGermanSymbol(symbol)
        guard !german || GermanMarketSession.isOpen(at: Date(timeIntervalSince1970: Double(nowEpochSeconds))) else {
            return nil
        }
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowEpochSeconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: german ? "Europe/Berlin" : "America/New_York")!
        let evaluationDate = Date(timeIntervalSince1970: Double(evaluationTime))
        let completed = bars.filter {
            $0.symbol == symbol && $0.isValid && $0.minuteEpochSeconds + 60 <= evaluationTime &&
                calendar.isDate(Date(timeIntervalSince1970: Double($0.minuteEpochSeconds)), inSameDayAs: evaluationDate)
        }.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds }
        guard let last = completed.last, last.minuteEpochSeconds >= evaluationTime - 180 else { return nil }
        let status = german ? delayedStatus : currentStatus
        return RapidCrashDetector.detect(symbol: symbol, bars: completed,
            nowEpochSeconds: evaluationTime, settings: settings.rapidCrash, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
            ?? RapidRiseDetector.detect(symbol: symbol, bars: completed,
                nowEpochSeconds: evaluationTime, settings: settings.rapidRise, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
            ?? SmoothRiseDetector.detect(symbol: symbol, bars: completed,
                nowEpochSeconds: evaluationTime, settings: settings.smoothRise, dataStatus: status, observedAtEpochSeconds: nowEpochSeconds)
    }
}
