import Foundation

actor RadarSignalBarBackfill {
    private let storeURL: URL?
    private let fetchBars: @Sendable (String) async throws -> [MinuteBar]
    private var attemptedAt: [String: Date] = [:]
    private var cooldownUntil: Date?
    private var store: MarketBarStore?
    private var activeChecks = 0

    init(
        storeURL: URL? = nil,
        fetchBars: @escaping @Sendable (String) async throws -> [MinuteBar] = {
            try await YahooRadarSource().minuteBars(symbol: $0)
        }
    ) {
        self.storeURL = storeURL
        self.fetchBars = fetchBars
    }

    func fillIfMissing(symbol: String) async -> Bool {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty, FinnhubBidAskClient.supports(symbol: normalized) else { return false }
        while activeChecks >= 4 {
            if Task.isCancelled { return false }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if Task.isCancelled { return false }
        activeChecks += 1
        defer { activeChecks -= 1 }
        let now = Date()
        if let cooldownUntil, now < cooldownUntil { return false }
        if let previous = attemptedAt[normalized], now.timeIntervalSince(previous) < 15 * 60 {
            return false
        }
        attemptedAt[normalized] = now

        do {
            let barStore: MarketBarStore
            if let store { barStore = store }
            else {
                let url = try storeURL ?? MarketBarStore.defaultURL()
                barStore = try MarketBarStore(url: url)
                store = barStore
            }
            let saved = try await barStore.loadRecentMinuteBars(
                symbol: normalized, fromEpochSeconds: 0,
                throughEpochSeconds: Int64(now.timeIntervalSince1970), limit: 1
            )
            guard saved.isEmpty else { return false }

            let bars = try await fetchBars(normalized)
            try Task.checkCancellation()
            guard !bars.isEmpty else { return false }
            _ = try await barStore.upsertBatch(Array(bars.suffix(360)))
            return true
        } catch is CancellationError {
            attemptedAt.removeValue(forKey: normalized)
            return false
        } catch RadarSourceError.rateLimited {
            cooldownUntil = Date().addingTimeInterval(30 * 60)
            return false
        } catch {
            AppDiagnostics.shared.record(
                .warning, "Radar", "signal-bar-backfill-failed",
                "symbol=\(normalized) error=\(String(describing: type(of: error)))"
            )
            return false
        }
    }
}
