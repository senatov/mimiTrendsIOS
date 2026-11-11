import Foundation

struct SymbolOutcome: Sendable {
    let symbol: String
    let received: Int
    let failure: String?
    var usable = false
    var rateLimited = false
    var rejectedSymbol: String?
    var unreadableSymbol: String?
    var skipped = false
    var missingVolume = false
}

enum RadarCandleScan {
    static func load(symbol: String, yahoo: YahooRadarSource, barStore: MarketBarStore,
                     nowSeconds: Int64, settings: RadarScanPreferences) async -> SymbolOutcome {
        do {
            let bars = try await yahoo.minuteBars(symbol: symbol, includeExtendedHours: true)
            try Task.checkCancellation()
            let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowSeconds)
            guard let last = bars.last, last.minuteEpochSeconds <= nowSeconds + 60,
                  last.minuteEpochSeconds >= evaluationTime - 600 else {
                RadarMarketDataPolicy.logStale(symbol: symbol, bars: bars, now: nowSeconds)
                return SymbolOutcome(symbol: symbol, received: bars.count, failure: nil, skipped: true)
            }
            let recent = bars.filter { $0.minuteEpochSeconds >= nowSeconds - MarketBarStore.retentionSeconds }
            let usable = recent.filter { $0.isValid && $0.volumeStatus == .reported }.count >= 2
            for start in stride(from: 0, to: recent.count, by: 360) {
                _ = try await barStore.upsertBatch(Array(recent[start..<min(start + 360, recent.count)]))
            }
            let signal = YahooCandleSignalPipeline.detect(symbol: symbol, bars: bars,
                nowEpochSeconds: nowSeconds, settings: settings, volumeValidated: true)
            if let signal {
                let finnhubMatches: Bool
                if MarketProviderAccess.isOperational(.finnhub) {
                    finnhubMatches = await FinnhubCandlePriceVerifier().matches(
                        signal: signal, latestBar: last, nowSeconds: nowSeconds)
                } else {
                    finnhubMatches = false
                }
                let recorded = finnhubMatches
                    ? YahooCandleSignalPipeline.detect(symbol: symbol, bars: bars,
                        nowEpochSeconds: nowSeconds, settings: settings, verified: true)
                    : signal
                let store = try MarketSignalStore(url: MarketSignalStore.defaultURL())
                if let recorded, try await store.record(recorded) {
                    AppDiagnostics.shared.record(.info, "Radar", "candle-signal-recorded",
                        "symbol=\(symbol) event=\(recorded.signalSource) window=\(recorded.signalWindowLabel) move=\(recorded.windowChangePercent) status=\(recorded.dataStatus) eventMillis=\(recorded.signalEpochMillis)")
                }
            }
            RadarMarketDataPolicy.logAccepted(symbol: symbol, bars: bars, now: nowSeconds)
            return SymbolOutcome(symbol: symbol, received: bars.count, failure: nil,
                usable: usable, skipped: !usable, missingVolume: !usable)
        } catch RadarSourceError.rateLimited {
            return SymbolOutcome(symbol: symbol, received: 0,
                failure: "Yahoo temporarily limited requests (HTTP 429). Radar pauses scanning for 30 minutes.", rateLimited: true)
        } catch RadarSourceError.invalidSymbol {
            return SymbolOutcome(symbol: symbol, received: 0, failure: nil, rejectedSymbol: symbol, skipped: true)
        } catch {
            if Task.isCancelled { return SymbolOutcome(symbol: symbol, received: 0, failure: nil, skipped: true) }
            var message = MarketRadarErrorDescription.message(error, provider: "Yahoo (\(symbol))")
            var unreadable: String?
            if case RadarSourceError.invalidResponse = error {
                unreadable = symbol
                let resolution = await YahooSymbolDiagnosisService().diagnose(symbol: symbol)
                await YahooSymbolResolutionStore.shared.save(resolution)
                message += " Auto-check: \(resolution.summary)"
                AppDiagnostics.shared.record(.warning, "Yahoo", "symbol-auto-diagnosed",
                    "symbol=\(symbol) evidence=\(resolution.providerEvidence.joined(separator: " | ")) recheckAtMillis=\(resolution.retryAfterMillis)")
            }
            return SymbolOutcome(symbol: symbol, received: 0, failure: message, unreadableSymbol: unreadable)
        }
    }
}

struct FinnhubCandlePriceVerifier: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func matches(signal: ScanResult, latestBar: MinuteBar, nowSeconds: Int64) async -> Bool {
        guard MarketProviderAccess.isEnabled(.finnhub),
              !MarketCandidateFilter.isGermanSymbol(signal.symbol),
              let key = try? FinnhubCredentialStore.load(), !key.isEmpty,
              let url = URL(string: "https://finnhub.io/api/v1/quote?symbol=\(signal.symbol)") else {
            return false
        }
        var request = URLRequest(url: url)
        request.setValue(key, forHTTPHeaderField: "X-Finnhub-Token")
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.count < 10_000,
                  let quote = try? JSONDecoder().decode(Quote.self, from: data) else { return false }
            return Self.isMatching(price: quote.current, timestamp: quote.timestamp,
                                   candlePrice: latestBar.close, nowSeconds: nowSeconds)
        } catch { return false }
    }

    static func isMatching(price: Double?, timestamp: Int64?, candlePrice: Double,
                           nowSeconds: Int64) -> Bool {
        guard let price, let timestamp, price.isFinite, price > 0, candlePrice > 0,
              timestamp >= nowSeconds - 180, timestamp <= nowSeconds + 30 else { return false }
        return abs(price / candlePrice - 1) <= 0.005
    }

    private struct Quote: Decodable {
        let current: Double?
        let timestamp: Int64?
        enum CodingKeys: String, CodingKey { case current = "c", timestamp = "t" }
    }
}
