import Foundation

enum BoerseQuoteRetryPolicy {
    static let minimumRetrySeconds: TimeInterval = 180

    static func shouldReload(staleSeconds: TimeInterval, progressSeconds: TimeInterval,
                             sinceReloadSeconds: TimeInterval, quoteAgeSeconds: Int?,
                             pageUnavailable: Bool) -> Bool {
        staleSeconds >= 90 && sinceReloadSeconds >= minimumRetrySeconds &&
            (progressSeconds >= minimumRetrySeconds ||
             quoteAgeSeconds.map { $0 >= 180 } == true || pageUnavailable)
    }
}

enum BoerseQuoteRows {
    struct Result {
        let samples: [BoerseQuoteSample]
        let diagnostics: String
        let newestQuoteMillis: Int64?
        let youngestAgeSeconds: Int?
    }

    static func decode(_ rows: [BoerseDAXSource.PageRow], now: Date, slot: Int) -> Result {
        var samples: [BoerseQuoteSample] = []
        var shaped = 0
        var identified = 0
        var priced = 0
        var timed = 0
        var recent = 0
        var sampleTime = "none"
        var sampleVenue = "none"
        var youngestAgeSeconds = Int.max
        var newestQuoteMillis: Int64?
        let nowMillis = Int64(now.timeIntervalSince1970 * 1_000)
        for row in rows {
            guard row.text.count == 14 else { continue }
            shaped += 1
            guard let isin = MarketPageHTML.first(#"\b([A-Z]{2}[A-Z0-9]{9}[0-9])\b"#, in: row.markup)
            else { continue }
            identified += 1
            guard let price = MarketPageHTML.germanNumber(row.text[5]) else { continue }
            priced += 1
            if sampleTime == "none" {
                sampleTime = String(row.text[12].replacingOccurrences(of: "\n", with: " ").prefix(24))
                sampleVenue = String(row.text[13].prefix(24))
            }
            guard let timestamp = MarketPageHTML.quoteTime(row.text[12], now: now) else { continue }
            timed += 1
            let ageSeconds = Int((nowMillis - timestamp) / 1_000)
            newestQuoteMillis = max(newestQuoteMillis ?? timestamp, timestamp)
            if ageSeconds < youngestAgeSeconds {
                youngestAgeSeconds = ageSeconds
                sampleTime = String(row.text[12].replacingOccurrences(of: "\n", with: " ").prefix(24))
                sampleVenue = String(row.text[13].prefix(24))
            }
            guard nowMillis - timestamp <= 90_000 else { continue }
            recent += 1
            let venue = row.text[13].uppercased()
            let currency: String
            if ["STU", "STUTTGART", "TRADEGATE", "XETRA", "FRA"].contains(venue) { currency = "EUR" }
            else if ["NASDAQ", "NAS", "NYSE", "NYS"].contains(venue) { currency = "USD" }
            else { continue }
            let ticker = slot == 0 ? BoerseDAXSource.knownSymbols[isin]?.symbol : nil
            samples.append(BoerseQuoteSample(isin: isin, symbol: ticker, currency: currency,
                                             venue: venue, timestamp: timestamp, price: price))
        }
        return Result(samples: samples, diagnostics:
            "rows=\(rows.count) shape=\(shaped) isin=\(identified) price=\(priced) time=\(timed) recent=\(recent) accepted=\(samples.count) youngestAgeSeconds=\(youngestAgeSeconds == Int.max ? -1 : youngestAgeSeconds) timeSample=\(sampleTime) venueSample=\(sampleVenue)",
            newestQuoteMillis: newestQuoteMillis,
            youngestAgeSeconds: youngestAgeSeconds == Int.max ? nil : youngestAgeSeconds)
    }
}

struct BoerseQuoteSample: Sendable {
    let isin: String
    let symbol: String?
    let currency: String
    let venue: String
    let timestamp: Int64
    let price: Double
}

actor BoerseQuoteMonitor {
    private struct Series {
        var timestamp: Int64
        var openBar: MinuteBar
        var completed: [MinuteBar] = []
    }

    private var series: [String: Series] = [:]
    private var tickers: [String: String] = [:]
    private var attempts: [String: Date] = [:]
    private var signalStore: MarketSignalStore?

    func accept(_ samples: [BoerseQuoteSample], settings: RadarScanPreferences) async throws -> Int {
        let now = Date()
        series = series.filter { now.timeIntervalSince1970 - Double($0.value.timestamp) / 1_000 < 3_600 }
        var stored = 0
        for sample in samples {
            try Task.checkCancellation()
            guard let ticker = sample.symbol ?? tickers[sample.isin] else { continue }
            if let signal = update(sample, ticker: ticker, settings: settings.validated) {
                if signalStore == nil { signalStore = try MarketSignalStore(url: MarketSignalStore.defaultURL()) }
                if try await signalStore?.record(signal) == true {
                    stored += 1
                    AppDiagnostics.shared.record(.info, "boerse.de", "quote-signal-stored",
                                                 "symbol=\(ticker) event=\(signal.signalSource) move=\(signal.windowChangePercent)")
                }
            }
        }
        var pending = Set<String>()
        for sample in samples where sample.symbol == nil && tickers[sample.isin] == nil {
            if now.timeIntervalSince(attempts[sample.isin] ?? .distantPast) > 900 { pending.insert(sample.isin) }
        }
        let batch = Array(pending.sorted().prefix(8))
        for isin in batch { attempts[isin] = now }
        await withTaskGroup(of: (String, String?).self) { tasks in
            for isin in batch {
                tasks.addTask { (isin, try? await RadarBaselineSource.searchISIN(isin, usOnly: true)) }
            }
            for await (isin, ticker) in tasks { tickers[isin] = ticker }
        }
        return stored
    }

    private func update(_ sample: BoerseQuoteSample, ticker: String, settings: RadarScanPreferences) -> ScanResult? {
        let minute = sample.timestamp / 60_000 * 60
        let key = "\(ticker)|\(sample.venue)|\(sample.currency)"
        let first = MinuteBar(symbol: ticker, minuteEpochSeconds: minute, open: sample.price,
            high: sample.price, low: sample.price, close: sample.price, volume: 0, volumeStatus: .missing)
        guard var history = series[key] else {
            series[key] = Series(timestamp: sample.timestamp, openBar: first)
            return nil
        }
        guard sample.timestamp > history.timestamp else { return nil }
        history.timestamp = sample.timestamp
        let previous = history.openBar
        if previous.minuteEpochSeconds == minute {
            history.openBar = MinuteBar(symbol: ticker, minuteEpochSeconds: minute, open: previous.open,
                high: max(previous.high, sample.price), low: min(previous.low, sample.price),
                close: sample.price, volume: 0, volumeStatus: .missing)
            series[key] = history
            return nil
        }
        if minute - previous.minuteEpochSeconds != 60 { history.completed.removeAll() }
        else { history.completed.append(previous) }
        history.completed = Array(history.completed.suffix(31))
        history.openBar = first
        series[key] = history
        guard let last = history.completed.last, last.close >= settings.minimumPrice else { return nil }
        let rules = [(settings.crashWindowMinutes, -settings.crashPercent),
                     (settings.sustainedCrashWindowMinutes, -settings.sustainedCrashPercent),
                     (settings.riseWindowMinutes, settings.risePercent)]
        for (minutes, threshold) in rules where history.completed.count > minutes {
            let start = history.completed[history.completed.count - minutes - 1]
            let change = (last.close / start.close - 1) * 100
            guard threshold > 0 ? change >= threshold : change <= threshold else { continue }
            let closeTime = minute * 1_000
            return ScanResult(symbol: ticker, price: last.close, priceCurrency: sample.currency,
                anomalyScore: 0, priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
                relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: change,
                windowVolume: 0, sessionVolume: 0, sessionTurnover: 0, signalAgeMinutes: 0,
                signalSource: change > 0 ? "boerse.de price rise" : "boerse.de price drop",
                updatedAtMillis: closeTime, dataStatus: "BOERSE_PRICE_NO_VOLUME",
                signalWindowLabel: "\(minutes)m", signalPrice: start.close, signalEpochMillis: closeTime,
                entryQualityLabel: "Price observations · volume unavailable")
        }
        return nil
    }
}
