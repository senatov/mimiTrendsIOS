import Foundation

struct LSQuoteObservation: Sendable {
    let instrumentID: String
    let observedAtMillis: Int64
    let bid: Double
    let ask: Double
    var midpoint: Double { (bid + ask) / 2 }
}

/// Detects executable quote movement without inventing trades or volume.
enum LSQuoteMoveDetector {
    static func detect(_ rows: [LSQuoteObservation], nowMillis: Int64,
                       settings: RadarScanPreferences) -> ScanResult? {
        let rows = rows.sorted { $0.observedAtMillis < $1.observedAtMillis }
        guard let end = rows.last, end.observedAtMillis <= nowMillis + 30_000,
              nowMillis - end.observedAtMillis <= 90_000,
              end.bid >= settings.minimumPrice else { return nil }
        let windows = [(settings.crashWindowMinutes, settings.crashPercent, false),
                       (settings.sustainedCrashWindowMinutes, settings.sustainedCrashPercent, false),
                       (settings.riseWindowMinutes, settings.risePercent, true)]
        for (minutes, threshold, rising) in windows {
            let cutoff = end.observedAtMillis - Int64(minutes) * 60_000
            let window = rows.filter { $0.observedAtMillis >= cutoff - 30_000 }
            guard let start = window.first, window.count >= 3,
                  start.observedAtMillis <= cutoff + 30_000,
                  window.allSatisfy({ $0.instrumentID == end.instrumentID &&
                      $0.bid.isFinite && $0.ask.isFinite && $0.bid > 0 && $0.ask >= $0.bid }),
                  !zip(window, window.dropFirst()).contains(where: {
                      $1.observedAtMillis - $0.observedAtMillis > 90_000
                  }) else { continue }
            let change = ((rising ? end.bid / start.ask : end.ask / start.bid) - 1) * 100
            guard rising ? change >= threshold : change <= -threshold else { continue }
            return ScanResult(
                symbol: "LS:\(end.instrumentID)", price: end.midpoint, priceCurrency: "EUR",
                anomalyScore: 0, priceAnomaly: nil, volumeAnomaly: nil, rangeAnomaly: nil,
                relativeVolume: nil, candleBodyRatio: 0, windowChangePercent: change,
                windowVolume: 0, sessionVolume: 0, sessionTurnover: 0,
                signalAgeMinutes: Int(max(0, nowMillis - end.observedAtMillis) / 60_000),
                signalSource: rising ? "L&S quote rise" : "L&S quote drop",
                updatedAtMillis: end.observedAtMillis, dataStatus: "QUOTE_NO_VOLUME",
                signalWindowLabel: "\(minutes)m", signalPrice: start.midpoint,
                signalEpochMillis: end.observedAtMillis, bidPrice: end.bid, askPrice: end.ask,
                executableQuoteAtMillis: end.observedAtMillis,
                entryQualityLabel: "Quote movement · volume unavailable",
                analysisUpdatedAtMillis: end.observedAtMillis, scanEvaluatedAtMillis: nowMillis
            )
        }
        return nil
    }
}
