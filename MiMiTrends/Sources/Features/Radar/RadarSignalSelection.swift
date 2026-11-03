import Foundation

enum RadarSignalSelection {
    static func displayHistory(_ history: [ScanResult], since cutoff: Int64, limit: Int)
        -> (signals: [ScanResult], savedFallback: Bool) {
        let fresh = history.filter { $0.signalEpochMillis >= cutoff }
        return (latestPerSymbol(fresh.isEmpty ? history : fresh, limit: limit),
                fresh.isEmpty && !history.isEmpty)
    }

    static func latestPerSymbol(_ signals: [ScanResult], limit: Int) -> [ScanResult] {
        var seen = Set<String>()
        return Array(signals.sorted { $0.signalEpochMillis > $1.signalEpochMillis }
            .filter { seen.insert($0.symbol).inserted }
            .prefix(max(0, limit)))
    }
}
