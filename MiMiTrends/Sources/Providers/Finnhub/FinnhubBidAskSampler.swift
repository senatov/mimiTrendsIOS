import Foundation

actor FinnhubBidAskSampler {
    private let load: @Sendable (String, String) async throws -> ProviderQuoteSnapshot
    private var lastAttemptAtMillis: Int64 = 0
    private var accessUnavailable = false
    private var cachedBySymbol: [String: ProviderQuoteSnapshot] = [:]

    init(load: @escaping @Sendable (String, String) async throws -> ProviderQuoteSnapshot = {
        try await FinnhubBidAskClient().load(symbol: $0, apiKey: $1)
    }) {
        self.load = load
    }

    func latest(symbol: String, apiKey: String, nowMillis: Int64) async -> ProviderQuoteSnapshot? {
        guard FinnhubBidAskClient.supports(symbol: symbol), !accessUnavailable else { return nil }
        if lastAttemptAtMillis == 0 || nowMillis - lastAttemptAtMillis >= 60_000 {
            lastAttemptAtMillis = nowMillis
            do {
                let quote = try await load(symbol, apiKey)
                try Task.checkCancellation()
                cachedBySymbol[symbol] = quote
                AppDiagnostics.shared.record(.info, "Finnhub", "bidask-sampled",
                                             "symbol=\(symbol) ageSeconds=\(max(0, nowMillis - quote.observedAtMillis) / 1_000)")
            } catch FinnhubBidAskError.accessUnavailable {
                accessUnavailable = true
                cachedBySymbol.removeAll()
                AppDiagnostics.shared.record(.warning, "Finnhub", "bidask-unavailable", "symbol=\(symbol) reason=access-denied")
            } catch {
                cachedBySymbol.removeValue(forKey: symbol)
                let nsError = error as NSError
                AppDiagnostics.shared.record(.warning, "Finnhub", "bidask-failed",
                    "symbol=\(symbol) errorType=\(String(describing: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)")
            }
        }
        guard let cached = cachedBySymbol[symbol],
              cached.observedAtMillis <= nowMillis,
              cached.observedAtMillis >= nowMillis - 120_000 else { return nil }
        return cached
    }
}
