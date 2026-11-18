enum MarketSignalFactory {
    static func make(
        symbol: String,
        bars: [MinuteBar],
        start: MinuteBar,
        end: MinuteBar,
        eventBarCount: Int,
        changePercent: Double,
        source: String,
        displayPrice: Double,
        nowEpochSeconds: Int64,
        anomalyScore: Double = 100,
        windowLabel: String? = nil,
        dataStatus: String? = nil,
        observedAtEpochSeconds: Int64? = nil
    ) -> ScanResult {
        let observedTime = observedAtEpochSeconds ?? nowEpochSeconds
        let event = bars.filter {
            $0.minuteEpochSeconds >= start.minuteEpochSeconds &&
                $0.minuteEpochSeconds <= end.minuteEpochSeconds
        }
        let session = bars.filter {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - 10_800 &&
                $0.minuteEpochSeconds <= end.minuteEpochSeconds
        }
        let recentTurnover = session.filter {
            $0.minuteEpochSeconds >= end.minuteEpochSeconds - 1_800 &&
                $0.volumeStatus == .reported
        }.reduce(0) { $0 + $1.close * $1.volume }
        return ScanResult(
            symbol: symbol,
            price: displayPrice,
            priceCurrency: symbol.uppercased().hasSuffix(".DE") ? "EUR" : "USD",
            anomalyScore: anomalyScore,
            priceAnomaly: nil,
            volumeAnomaly: nil,
            rangeAnomaly: nil,
            relativeVolume: nil,
            candleBodyRatio: 0,
            windowChangePercent: changePercent,
            windowVolume: (source == "Tradable corridor" ? Array(session.suffix(eventBarCount)) : event)
                .reduce(0) { $0 + $1.volume },
            sessionVolume: session.reduce(0) { $0 + $1.volume },
            sessionTurnover: session.reduce(0) { $0 + $1.close * $1.volume },
            signalAgeMinutes: Int(max(0, observedTime - end.minuteEpochSeconds) / 60),
            signalSource: source,
            updatedAtMillis: end.minuteEpochSeconds * 1_000,
            dataStatus: dataStatus ?? (MarketCandidateFilter.isGermanSymbol(symbol) ? "DELAYED" : "LIVE"),
            signalWindowLabel: windowLabel ?? "\(max(1, (end.minuteEpochSeconds - start.minuteEpochSeconds) / 60))m",
            signalPrice: start.close,
            signalEpochMillis: end.minuteEpochSeconds * 1_000,
            analysisUpdatedAtMillis: end.minuteEpochSeconds * 1_000,
            scanEvaluatedAtMillis: observedTime * 1_000,
            anchorCandle: start, eventCandle: end, recentTurnover: recentTurnover
        )
    }
}
