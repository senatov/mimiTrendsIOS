import Foundation

/// A selected chart must load its own candles even when the ticker is outside the scan pool.
actor RadarSelectedCandleHistory {
    static let shared = RadarSelectedCandleHistory()
    private let storeURL: URL?
    private let fetch: @Sendable (String) async throws -> [MinuteBar]
    private var attemptedAt: [String: Date] = [:]
    private var pending: [String: Task<[MinuteBar], Error>] = [:]
    private var cooldownUntil = Date.distantPast

    init(storeURL: URL? = nil,
         fetch: @escaping @Sendable (String) async throws -> [MinuteBar] = {
             try await YahooRadarSource().minuteBars(symbol: $0)
         }) {
        self.storeURL = storeURL
        self.fetch = fetch
    }

    func load(symbol: String, yahooEnabled: Bool, now: Date = Date()) async throws -> [MinuteBar] {
        let store = try MarketBarStore(url: storeURL ?? MarketBarStore.defaultURL())
        let nowSeconds = Int64(now.timeIntervalSince1970)
        let saved = try await store.loadRecentMinuteBars(symbol: symbol, fromEpochSeconds: 0,
            throughEpochSeconds: nowSeconds, limit: 2_000)
        guard yahooEnabled else { return saved }
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowSeconds)
        if let last = saved.last, last.minuteEpochSeconds >= evaluationTime - 90 { return saved }
        if let task = pending[symbol] { return try await task.value }
        guard now >= cooldownUntil else {
            if saved.isEmpty { throw RadarSourceError.rateLimited }
            return saved
        }
        if let previous = attemptedAt[symbol], now.timeIntervalSince(previous) < 60 { return saved }
        attemptedAt[symbol] = now
        let task = Task { [fetch] in
            let fetched = try await fetch(symbol)
            try Task.checkCancellation()
            for start in stride(from: 0, to: fetched.count, by: 360) {
                _ = try await store.upsertBatch(Array(fetched[start..<min(start + 360, fetched.count)]))
            }
            let bars = try await store.loadRecentMinuteBars(symbol: symbol, fromEpochSeconds: 0,
                throughEpochSeconds: nowSeconds, limit: 2_000)
            AppDiagnostics.shared.record(.info, "RadarChart", "selected-candles-loaded",
                                         "symbol=\(symbol) fetched=\(fetched.count) saved=\(bars.count)")
            return bars
        }
        pending[symbol] = task
        defer { pending[symbol] = nil }
        do { return try await task.value }
        catch {
            if case RadarSourceError.rateLimited = error { cooldownUntil = now.addingTimeInterval(30 * 60) }
            AppDiagnostics.shared.record(.warning, "RadarChart", "selected-candles-failed",
                                         "symbol=\(symbol) saved=\(saved.count) error=\(String(describing: error))")
            if !saved.isEmpty { return saved }
            throw error
        }
    }
}
