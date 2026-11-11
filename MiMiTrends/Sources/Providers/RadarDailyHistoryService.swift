import Foundation

struct RadarDailyHistory: Sendable {
    let bars: [MinuteBar]
    let provider: String
}

actor RadarDailyHistoryService {
    static let shared = RadarDailyHistoryService()

    func load(symbol: String) async throws -> RadarDailyHistory {
        let store = try MarketBarStore(url: MarketBarStore.finnhubURL())
        var calendar = Calendar(identifier: .gregorian)
        let german = MarketCandidateFilter.isGermanSymbol(symbol)
        calendar.timeZone = TimeZone(identifier: german ? "Europe/Berlin" : "America/New_York") ?? .gmt
        let cutoff = calendar.date(byAdding: .day, value: -366, to: Date()) ?? Date()
        var cursor = Int64(cutoff.timeIntervalSince1970)
        var days: [Int64: MinuteBar] = [:]
        while true {
            try Task.checkCancellation()
            let page = try await store.loadMinuteBars(symbol: symbol, fromEpochSeconds: cursor)
            for bar in page {
                let date = Date(timeIntervalSince1970: Double(bar.minuteEpochSeconds))
                let day = Int64(calendar.startOfDay(for: date).timeIntervalSince1970)
                if let previous = days[day] {
                    days[day] = MinuteBar(symbol: bar.symbol, minuteEpochSeconds: day,
                        open: previous.open, high: max(previous.high, bar.high),
                        low: min(previous.low, bar.low), close: bar.close,
                        volume: previous.volume + bar.volume)
                } else {
                    days[day] = MinuteBar(symbol: bar.symbol, minuteEpochSeconds: day, open: bar.open,
                        high: bar.high, low: bar.low, close: bar.close, volume: bar.volume,
                        volumeStatus: bar.volumeStatus)
                }
            }
            guard page.count == 10_000, let last = page.last else { break }
            cursor = last.minuteEpochSeconds + 1
        }
        return RadarDailyHistory(bars: days.values.sorted { $0.minuteEpochSeconds < $1.minuteEpochSeconds },
                                 provider: "Saved Finnhub")
    }
}
