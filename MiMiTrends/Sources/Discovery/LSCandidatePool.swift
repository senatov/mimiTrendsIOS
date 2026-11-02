import Foundation

struct LSCandidateStatus: Sendable {
    let quotes: [MarketPageQuote]
    let moves: [LSQuoteMove]
    let lastSuccessAtMillis: Int64?
    let lastAttemptSucceeded: Bool
    let requestCount: Int
    let errorCount: Int

    func freshCount(atMillis now: Int64) -> Int {
        quotes.filter { now - $0.observedAtMillis >= -30 && now - $0.observedAtMillis <= 600_000 }.count
    }
}

struct LSQuoteMove: Sendable, Identifiable {
    let quote: MarketPageQuote
    let changePercent: Double
    let fromMillis: Int64

    var id: String { quote.identifier }
}

actor LSCandidatePool {
    private let source: LangSchwarzQuoteSource
    private var quotes: [MarketPageQuote] = []
    private var observations: [String: [MarketPageQuote]] = [:]
    private var lastStoredQuotes: [String: MarketPageQuote] = [:]
    private var moves: [LSQuoteMove] = []
    private var lastSuccessAtMillis: Int64?
    private var lastAttemptSucceeded = false
    private var nextAttemptAtMillis: Int64 = 0
    private var requestCount = 0
    private var errorCount = 0

    init(source: LangSchwarzQuoteSource = LangSchwarzQuoteSource()) {
        self.source = source
    }

    func stop() -> LSCandidateStatus {
        observations = [:]
        moves = []
        lastAttemptSucceeded = false
        nextAttemptAtMillis = 0
        return status()
    }

    func refreshIfNeeded(settings: RadarScanPreferences) async -> LSCandidateStatus {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        guard now >= nextAttemptAtMillis else { return status() }
        requestCount += 1
        do {
            let loaded = try await source.loadQuotes()
            try Task.checkCancellation()
            let store = try MarketQuoteStore(url: MarketQuoteStore.defaultURL())
            let storageTime = Int64(Date().timeIntervalSince1970 * 1_000)
            let changed = loaded.filter { quote in
                guard storageTime - quote.observedAtMillis <= 570_000 else { return false }
                guard let previous = lastStoredQuotes[quote.identifier] else { return true }
                let priceChange = abs(quote.midpointEUR / previous.midpointEUR - 1)
                return priceChange >= 0.0001 ||
                    abs(quote.askEUR - quote.bidEUR - (previous.askEUR - previous.bidEUR)) >= 0.0001
            }
            _ = try await store.record(changed.map(MarketQuoteRecord.init), nowMillis: storageTime)
            for quote in changed { lastStoredQuotes[quote.identifier] = quote }
            quotes = loaded
            recordFreshObservations(loaded, settings: settings.validated)
            lastSuccessAtMillis = Int64(Date().timeIntervalSince1970 * 1_000)
            lastAttemptSucceeded = true
            nextAttemptAtMillis = lastSuccessAtMillis! + 30_000
            AppDiagnostics.shared.record(.info, "LangSchwarz", "refresh-success",
                                         "quotes=\(loaded.count) moves=\(moves.count)")
        } catch {
            if Task.isCancelled || error is CancellationError { return status() }
            lastAttemptSucceeded = false
            errorCount += 1
            nextAttemptAtMillis = now + 5 * 60_000
            AppDiagnostics.shared.record(.warning, "LangSchwarz", "refresh-failed",
                                         "error=\(String(describing: type(of: error)))")
        }
        return status()
    }

    private func status() -> LSCandidateStatus {
        LSCandidateStatus(quotes: quotes, moves: moves, lastSuccessAtMillis: lastSuccessAtMillis,
                          lastAttemptSucceeded: lastAttemptSucceeded,
                          requestCount: requestCount, errorCount: errorCount)
    }

    private func recordFreshObservations(_ loaded: [MarketPageQuote], settings: RadarScanPreferences) {
        let now = Int64(Date().timeIntervalSince1970 * 1_000)
        var updatedMoves: [LSQuoteMove] = []
        for quote in loaded where now - quote.observedAtMillis >= 0 && now - quote.observedAtMillis <= 90_000 {
            let spread = (quote.askEUR - quote.bidEUR) / quote.midpointEUR * 100
            guard spread <= 0.30, quote.midpointEUR >= settings.minimumPrice else { continue }
            var history = observations[quote.identifier, default: []]
            history.removeAll { now - $0.observedAtMillis > 15 * 60_000 }
            if history.last.map({ $0.observedAtMillis < quote.observedAtMillis }) ?? true {
                history.append(quote)
            }
            observations[quote.identifier] = history
            let baseline = history.first { prior in
                quote.observedAtMillis - prior.observedAtMillis >= 2 * 60_000 &&
                    quote.observedAtMillis - prior.observedAtMillis <= 5 * 60_000
            }
            guard let baseline else { continue }
            let change = (quote.midpointEUR / baseline.midpointEUR - 1) * 100
            guard change >= settings.risePercent || change <= -settings.crashPercent else { continue }
            updatedMoves.append(LSQuoteMove(quote: quote, changePercent: change,
                                            fromMillis: baseline.observedAtMillis))
        }
        moves = updatedMoves.sorted { abs($0.changePercent) > abs($1.changePercent) }.prefix(20).map { $0 }
    }
}
