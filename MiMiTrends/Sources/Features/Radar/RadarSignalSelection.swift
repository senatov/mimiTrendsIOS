import Foundation

enum RadarSignalSelection {
    static func displayHistory(
        _ history: [ScanResult], since cutoff: Int64, limit: Int,
        preferences: RadarScanPreferences = RadarScanPreferences()
    ) -> [ScanResult] {
        let qualified = history.filter { signal in
            guard signal.dataStatus != "QUOTE_NO_VOLUME", signal.dataStatus != "FINNHUB_LIVE",
                  !signal.symbol.hasPrefix("LS:") else { return false }
            let source = signal.signalSource.lowercased()
            let requiresLiveTrades = ["rapid crash", "rapid rise", "sharp rebound", "smooth rise"].contains(source)
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
