import Foundation

enum RadarSignalSelection {
    static func displayHistory(
        _ history: [ScanResult], since cutoff: Int64, limit: Int,
        preferences: RadarScanPreferences = RadarScanPreferences(),
        allowSavedFallback: Bool = true
    )
        -> (signals: [ScanResult], savedFallback: Bool) {
        let qualified = history.filter { signal in
            let source = signal.signalSource.lowercased()
            let requiresLiveTrades = ["rapid crash", "sharp rebound", "smooth rise"].contains(source)
            if requiresLiveTrades && signal.dataStatus != "FINNHUB_LIVE" {
                return false
            }
            guard source == "rapid crash" else { return true }
            let minutes = Int(signal.signalWindowLabel.prefix { $0.isNumber }) ?? Int.max
            let threshold = minutes <= preferences.crashWindowMinutes
                ? preferences.crashPercent : preferences.sustainedCrashPercent
            return abs(signal.windowChangePercent) >= threshold
        }
        let fresh = qualified.filter { $0.signalEpochMillis >= cutoff }
        let fallback = allowSavedFallback && fresh.isEmpty && !qualified.isEmpty
        return (latestPerSymbol(fallback ? qualified : fresh, limit: limit), fallback)
    }

    static func latestPerSymbol(_ signals: [ScanResult], limit: Int) -> [ScanResult] {
        var seen = Set<String>()
        return Array(signals.sorted { $0.signalEpochMillis > $1.signalEpochMillis }
            .filter { seen.insert($0.symbol).inserted }
            .prefix(max(0, limit)))
    }
}
