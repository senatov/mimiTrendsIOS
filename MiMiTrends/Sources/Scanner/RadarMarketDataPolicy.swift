import Foundation

/// Xetra's public Yahoo feed is delayed; event times remain the original candle times.
enum RadarMarketDataPolicy {
    static func evaluationTime(symbol: String, now: Int64) -> Int64 {
        now - (MarketCandidateFilter.isGermanSymbol(symbol) ? 900 : 0)
    }

    static func logStale(symbol: String, bars: [MinuteBar], now: Int64) {
        AppDiagnostics.shared.record(.warning, "Yahoo", "no-current-candles",
                                     details(symbol: symbol, bars: bars, now: now))
    }

    static func logAccepted(symbol: String, bars: [MinuteBar], now: Int64) {
        AppDiagnostics.shared.record(.info, "Yahoo", "candles-accepted",
                                     details(symbol: symbol, bars: bars, now: now))
    }

    private static func details(symbol: String, bars: [MinuteBar], now: Int64) -> String {
        "symbol=\(symbol) bars=\(bars.count) ageSeconds=\(bars.last.map { now - $0.minuteEpochSeconds } ?? -1)"
    }
}

extension Array where Element == String {
    func appendingUnique(_ other: [String]) -> [String] {
        var seen = Set(self)
        return self + other.filter { seen.insert($0).inserted }
    }
}
