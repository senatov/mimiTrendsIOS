import Foundation

/// Yahoo retains only recent minute history; fetch actual candles for imported trade dates.
actor RadarTradeBarBackfill {
    static let shared = RadarTradeBarBackfill()
    private var attemptedAt: [String: Date] = [:]
    private var cooldownUntil: Date?

    func fill(symbol: String, trades: [BrokerTradePosition]) async {
        guard MarketCandidateFilter.supportsYahooBars(symbol: symbol), !trades.isEmpty else { return }
        let now = Date()
        if let cooldownUntil, now < cooldownUntil { return }
        let seconds = Int64(now.timeIntervalSince1970)
        let events: [Int64] = trades.flatMap { trade -> [Int64] in
            [trade.entryEpochSeconds, trade.exitEpochSeconds ?? trade.entryEpochSeconds]
        }
        let cutoff: Int64 = seconds - 6 * 86_400
        let recent = events.filter { $0 >= cutoff && $0 <= seconds }
        let uniqueDays = Set(recent.map { $0 / 86_400 * 86_400 })
        let days = uniqueDays.sorted().suffix(3)
        for day in days {
            if Task.isCancelled { return }
            let key = "\(symbol)|\(day)"
            if let attempted = attemptedAt[key], now.timeIntervalSince(attempted) < 15 * 60 { continue }
            attemptedAt[key] = now
            do {
                let bars = try await YahooRadarSource().historicalMinuteBars(
                    symbol: symbol, from: day, through: min(day + 86_400, seconds))
                let store = try MarketBarStore(url: MarketBarStore.defaultURL())
                for bar in bars { _ = try await store.upsert(bar) }
                AppDiagnostics.shared.record(.info, "RadarChart", "trade-history-loaded",
                                             "symbol=\(symbol) bars=\(bars.count) day=\(day)")
            } catch RadarSourceError.rateLimited {
                cooldownUntil = now.addingTimeInterval(30 * 60)
                return
            } catch {
                AppDiagnostics.shared.record(.warning, "RadarChart", "trade-history-unavailable",
                                             "symbol=\(symbol) day=\(day)")
            }
        }
    }
}
