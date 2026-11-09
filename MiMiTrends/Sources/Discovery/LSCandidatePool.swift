import Foundation

struct LSCandidateStatus: Sendable {
    let quotes: [MarketPageQuote]
    let lastSuccessAtMillis: Int64?
    let lastAttemptSucceeded: Bool
    let requestCount: Int
    let errorCount: Int

    func freshCount(atMillis now: Int64) -> Int {
        quotes.filter { now - $0.observedAtMillis >= -30 && now - $0.observedAtMillis <= 600_000 }.count
    }
}

actor LSCandidatePool {
    private let source: LangSchwarzQuoteSource
    private var quotes: [MarketPageQuote] = []
    private var lastStoredQuotes: [String: MarketPageQuote] = [:]
    private var lastSuccessAtMillis: Int64?
    private var lastAttemptSucceeded = false
    private var nextAttemptAtMillis: Int64 = 0
    private var requestCount = 0
    private var errorCount = 0

    init(source: LangSchwarzQuoteSource = LangSchwarzQuoteSource()) {
        self.source = source
    }

    func stop() -> LSCandidateStatus {
        lastAttemptSucceeded = false
        nextAttemptAtMillis = 0
        return status()
    }

    func refreshIfNeeded() async -> LSCandidateStatus {
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
                return storageTime - previous.observedAtMillis >= 30_000 || priceChange >= 0.0001 ||
                    abs(quote.askEUR - quote.bidEUR - (previous.askEUR - previous.bidEUR)) >= 0.0001
            }
            _ = try await store.record(changed.map(MarketQuoteRecord.init), nowMillis: storageTime)
            for quote in changed { lastStoredQuotes[quote.identifier] = quote }
            let observations = try await store.loadLS(sinceMillis: storageTime - 32 * 60_000)
            let signalStore = try MarketSignalStore(url: MarketSignalStore.defaultURL())
            let settings = RadarScanPreferencesStore.load()
            var savedSignals = 0
            for history in Dictionary(grouping: observations, by: \.instrumentID).values {
                if let signal = LSQuoteMoveDetector.detect(history, nowMillis: storageTime, settings: settings),
                   try await signalStore.record(signal) { savedSignals += 1 }
            }
            AppDiagnostics.shared.record(.info, "LangSchwarz", "quote-scan-finished",
                                         "observations=\(observations.count) signals=\(savedSignals)")
            quotes = loaded
            lastSuccessAtMillis = Int64(Date().timeIntervalSince1970 * 1_000)
            lastAttemptSucceeded = true
            nextAttemptAtMillis = lastSuccessAtMillis! + 30_000
            AppDiagnostics.shared.record(.info, "LangSchwarz", "refresh-success",
                                         "quotes=\(loaded.count)")
        } catch LangSchwarzQuoteError.noFreshQuotes {
            if Task.isCancelled { return status() }
            lastAttemptSucceeded = false
            let nowDate = Date()
            let quoteSessionOpen = LangSchwarzMarketSession.isQuoteVenueOpen(at: nowDate)
            let retryMillis: Int64 = quoteSessionOpen ? 60_000 : 300_000
            nextAttemptAtMillis = now + retryMillis
            AppDiagnostics.shared.record(.info, "LangSchwarz", "refresh-no-fresh-quotes",
                "lsQuoteSession=\(quoteSessionOpen ? "open" : "closed") underlyingOpen=\(LangSchwarzMarketSession.underlyingOpenEndpoints(at: nowDate).map(\.rawValue).joined(separator: ",")) retrySeconds=\(retryMillis / 1_000) errorsUnchanged=true")
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
        LSCandidateStatus(quotes: quotes, lastSuccessAtMillis: lastSuccessAtMillis,
                          lastAttemptSucceeded: lastAttemptSucceeded,
                          requestCount: requestCount, errorCount: errorCount)
    }
}
