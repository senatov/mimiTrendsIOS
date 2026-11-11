import Foundation

struct SymbolOutcome: Sendable {
    let symbol: String
    let received: Int
    let failure: String?
    var rateLimited = false
    var rejectedSymbol: String?
    var unreadableSymbol: String?
    var skipped = false
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
            for start in stride(from: 0, to: bars.count, by: 360) {
                _ = try await barStore.upsertBatch(Array(bars[start..<min(start + 360, bars.count)]))
            }
            let signal = YahooCandleSignalPipeline.detect(symbol: symbol, bars: bars,
                nowEpochSeconds: nowSeconds, settings: settings)
            if let signal {
                let store = try MarketSignalStore(url: MarketSignalStore.defaultURL())
                if try await store.record(signal) {
                    AppDiagnostics.shared.record(.info, "Radar", "candle-signal-recorded",
                        "symbol=\(symbol) event=\(signal.signalSource) window=\(signal.signalWindowLabel) move=\(signal.windowChangePercent) status=\(signal.dataStatus) eventMillis=\(signal.signalEpochMillis)")
                }
            }
            RadarMarketDataPolicy.logAccepted(symbol: symbol, bars: bars, now: nowSeconds)
            return SymbolOutcome(symbol: symbol, received: bars.count, failure: nil)
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
