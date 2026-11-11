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
            let history = try await yahoo.minuteHistory(symbol: symbol, includeExtendedHours: true)
            let bars = history.bars
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
                if let name = history.companyName {
                    await saveCompanyName(name, symbol: symbol, nowSeconds: nowSeconds)
                }
                let store = try MarketSignalStore(url: MarketSignalStore.defaultURL())
                if try await store.record(signal) {
                    AppDiagnostics.shared.record(.info, "Radar", "candle-signal-recorded",
                        "symbol=\(symbol) event=\(signal.signalSource) window=\(signal.signalWindowLabel) move=\(signal.windowChangePercent) status=\(signal.dataStatus) eventMillis=\(signal.signalEpochMillis)")
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

    private static func saveCompanyName(_ name: String, symbol: String, nowSeconds: Int64) async {
        do {
            let store = try RadarCompanyMetadataStore(url: RadarCompanyMetadataStore.defaultURL())
            let cached = try await store.load(symbols: [symbol])[symbol]
            try await store.save(RadarCompanyMetadata(
                symbol: symbol, name: name,
                countryCode: cached?.countryCode ?? RadarCompanyMetadata.listingCountry(for: symbol),
                logoData: cached?.logoData, updatedAtMillis: nowSeconds * 1_000
            ))
        } catch {
            AppDiagnostics.shared.record(.warning, "Radar", "company-name-cache-failed",
                "symbol=\(symbol) error=\(String(describing: type(of: error)))")
        }
    }
}
