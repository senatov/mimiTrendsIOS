import Foundation

enum RadarSignalSelection {
    static func withGermanReserve(_ confirmed: [ScanResult], watch: [ScanResult], limit: Int) -> [ScanResult] {
        guard limit > 0 else { return [] }
        let german = confirmed.filter { MarketCandidateFilter.isGermanSymbol($0.symbol) }
        let reserve = Array((german.isEmpty ? watch : german).prefix(min(5, limit)))
        let excluded = Set(reserve.map(\.symbol))
        let others = confirmed.filter { !excluded.contains($0.symbol) }
        let capacity = max(0, limit - reserve.count)
        return (reserve + Array(others.prefix(capacity))).sorted { $0.signalEpochMillis > $1.signalEpochMillis }
    }

    static func displayHistory(
        _ history: [ScanResult], since cutoff: Int64, limit: Int,
        preferences: RadarScanPreferences = RadarScanPreferences(),
        latestBars: [String: MinuteBar] = [:]
    ) -> [ScanResult] {
        let qualified = history.filter { signal in
            guard signal.dataStatus != "QUOTE_NO_VOLUME", signal.dataStatus != "FINNHUB_LIVE",
                  !signal.symbol.hasPrefix("LS:") else { return false }
            let source = signal.signalSource.lowercased()
            guard source != "rapid rise", source != "sharp rebound" else { return false }
            if source == "confirmed reversal", let latest = latestBars[signal.symbol],
               latest.minuteEpochSeconds * 1_000 > signal.signalEpochMillis,
               latest.close <= signal.signalPrice {
                return false
            }
            let requiresLiveTrades = ["rapid crash", "confirmed reversal", "smooth rise"].contains(source)
            let validatedYahoo = signal.dataStatus == YahooCandleSignalPipeline.volumeValidatedStatus ||
                signal.dataStatus == YahooCandleSignalPipeline.delayedVolumeValidatedStatus
            guard !signal.dataStatus.hasPrefix("YAHOO_CANDLES") || validatedYahoo else { return false }
            if validatedYahoo {
                let minutes = Int(signal.signalWindowLabel.prefix { $0.isNumber }) ?? Int.max
                guard minutes <= 30 else { return false }
            }
            if requiresLiveTrades && !validatedYahoo {
                return false
            }
            guard source == "rapid crash" else { return true }
            let minutes = Int(signal.signalWindowLabel.prefix { $0.isNumber }) ?? Int.max
            let threshold = minutes <= preferences.crashWindowMinutes
                ? preferences.crashPercent : preferences.sustainedCrashPercent
            return abs(signal.windowChangePercent) >= threshold
        }
        let fresh = qualified.filter { $0.signalEpochMillis >= cutoff }
        return latestPerSymbol(fresh, limit: limit)
    }

    static func latestPerSymbol(_ signals: [ScanResult], limit: Int) -> [ScanResult] {
        var seen = Set<String>()
        return Array(signals.sorted { $0.signalEpochMillis > $1.signalEpochMillis }
            .filter { seen.insert($0.symbol).inserted }
            .prefix(max(0, limit)))
    }
}

enum RadarGermanWatchCandidates {
    static let source = "German watch candidate"
    static let dataStatus = "GERMAN_RELAXED_WATCH"

    static func load(symbols: Set<String>, now: Date, settings: RadarScanPreferences) async -> [ScanResult] {
        guard !symbols.isEmpty, let store = try? MarketBarStore(url: MarketBarStore.defaultURL()) else { return [] }
        let nowSeconds = Int64(now.timeIntervalSince1970)
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: "SAP.DE", now: nowSeconds)
        var barsBySymbol: [String: [MinuteBar]] = [:]
        for symbol in symbols.sorted() {
            if Task.isCancelled { return [] }
            barsBySymbol[symbol] = try? await store.loadRecentMinuteBars(
                symbol: symbol, fromEpochSeconds: evaluationTime - 15 * 60,
                throughEpochSeconds: evaluationTime, limit: 30
            )
        }
        return select(barsBySymbol: barsBySymbol, now: now, settings: settings)
    }

    static func select(barsBySymbol: [String: [MinuteBar]], now: Date,
                       settings: RadarScanPreferences) -> [ScanResult] {
        let evaluationTime = RadarMarketDataPolicy.evaluationTime(
            symbol: "SAP.DE", now: Int64(now.timeIntervalSince1970))
        let windowMinutes = max(5, settings.crashWindowMinutes, settings.riseWindowMinutes)
        let windowSeconds = Int64(windowMinutes * 60)
        let available = barsBySymbol.compactMap { entry -> ScanResult? in
            let (symbol, bars) = entry
            guard MarketCandidateFilter.isGermanSymbol(symbol),
                  let latest = bars.last(where: { $0.minuteEpochSeconds + 60 <= evaluationTime }),
                  latest.isValid, latest.close >= settings.minimumPrice,
                  latest.minuteEpochSeconds >= evaluationTime - 600,
                  latest.volumeStatus == .reported, latest.volume > 0 else { return nil }
            let anchors = bars.filter {
                let span = latest.minuteEpochSeconds - $0.minuteEpochSeconds
                return span >= 60 && span <= windowSeconds && $0.isValid &&
                    $0.volumeStatus == .reported && $0.volume > 0 && $0.close > 0
            }
            guard let anchor = anchors.max(by: {
                abs(latest.close / $0.close - 1) < abs(latest.close / $1.close - 1)
            }) else { return nil }
            let change = (latest.close / anchor.close - 1) * 100
            guard abs(change) > 0.0001 else { return nil }
            let timestamp = latest.minuteEpochSeconds * 1_000
            return ScanResult(symbol: symbol, price: latest.close, priceCurrency: "EUR",
                anomalyScore: 0, priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
                relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: change,
                windowVolume: 0, sessionVolume: 0, sessionTurnover: 0, signalAgeMinutes: 0,
                signalSource: source, updatedAtMillis: timestamp, dataStatus: dataStatus,
                signalWindowLabel: "\(windowMinutes)m", signalPrice: anchor.close,
                signalEpochMillis: timestamp,
                entryQualityLabel: "Watch candidate · relaxed movement threshold",
                entryQualityDetails: "Recent German candle movement; confirmed signal rules were not met.")
        }.sorted {
            abs($0.windowChangePercent) == abs($1.windowChangePercent)
                ? $0.signalEpochMillis > $1.signalEpochMillis
                : abs($0.windowChangePercent) > abs($1.windowChangePercent)
        }
        var threshold = min(settings.crashPercent, settings.risePercent)
        while threshold > 0.01 && available.filter({ abs($0.windowChangePercent) >= threshold }).count < 3 {
            threshold *= 0.75
        }
        if available.filter({ abs($0.windowChangePercent) >= threshold }).count < 3 { threshold = 0 }
        return Array(available.filter { abs($0.windowChangePercent) >= threshold }.prefix(5))
    }
}
