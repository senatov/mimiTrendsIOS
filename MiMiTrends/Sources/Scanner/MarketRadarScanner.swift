import Foundation

struct RadarSourceTotals: Sendable {
    var received = 0
    var valid = 0
    var operations = 0
    var errors = 0
}

struct MarketRadarCycle: Sendable {
    let yahoo: RadarSourceTotals
    let traderFox: RadarSourceTotals
    let yahooCooldownUntil: Date?
    let initialScanProcessed: Int
    let initialScanTotal: Int
    let scannedSymbols: Int
    let storedSignals: Int
    let companyNames: [String: String]
}

actor MarketRadarScanner {
    private let yahoo = YahooRadarSource()
    private let traderFox = TraderFoxRadarSource()
    private var yahooCandidates: [RadarCompanyCandidate] = []
    private var traderFoxCandidates: [RadarCompanyCandidate] = []
    private var nextDiscoveryAt: Date = .distantPast
    private var yahooCooldownUntil: Date?
    private var unsupportedSymbols = Set<String>()
    private var scanOffset = 0
    private var initialScanSymbols = Set<String>()
    private var initialScanTotal = 0
    private var yahooTotals = RadarSourceTotals()
    private var traderFoxTotals = RadarSourceTotals()

    func scan(settings: RadarScanPreferences) async throws -> MarketRadarCycle {
        try Task.checkCancellation()
        if Date() >= nextDiscoveryAt {
            await refreshSources()
        }
        let pool = Self.interleave(yahooCandidates.map(\.symbol), traderFoxCandidates.map(\.symbol), limit: 16)
            .filter { !unsupportedSymbols.contains($0) }
        if initialScanTotal == 0 { initialScanTotal = pool.count }
        let names = Dictionary(
            (yahooCandidates + traderFoxCandidates).map { ($0.symbol, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        if let yahooCooldownUntil, Date() < yahooCooldownUntil {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    yahooCooldownUntil: yahooCooldownUntil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, storedSignals: 0, companyNames: names)
        }
        yahooCooldownUntil = nil
        let symbols = Self.scanSlice(pool, offset: scanOffset, limit: 4)
        if !pool.isEmpty { scanOffset = (scanOffset + symbols.count) % pool.count }
        guard !symbols.isEmpty else {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    yahooCooldownUntil: nil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, storedSignals: 0, companyNames: names)
        }
        let barStore = try MarketBarStore(url: MarketBarStore.defaultURL())
        let signalStore = try MarketSignalStore(url: MarketSignalStore.defaultURL())
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        var storedSignals = 0
        var firstYahooFailure: String?
        var yahooFailuresThisCycle = 0
        var rejectedSymbolsThisCycle = 0
        var firstRejectedSymbol: String?
        var rateLimited = false
        for batch in stride(from: 0, to: symbols.count, by: 4) {
            try Task.checkCancellation()
            let group = Array(symbols[batch..<min(batch + 4, symbols.count)])
            await withTaskGroup(of: SymbolOutcome.self) { tasks in
                for symbol in group {
                    tasks.addTask { [yahoo] in
                        do {
                            let bars = try await yahoo.minuteBars(symbol: symbol)
                            try Task.checkCancellation()
                            guard let last = bars.last,
                                  last.minuteEpochSeconds >= nowSeconds - 600 else {
                                return SymbolOutcome(received: bars.count, signalStored: false, failure: nil)
                            }
                            for bar in bars { _ = try await barStore.upsert(bar) }
                            let recent = try await barStore.loadMinuteBars(
                                symbol: symbol, fromEpochSeconds: nowSeconds - 21_600
                            )
                            let signal = RapidCrashDetector.detect(
                                symbol: symbol, bars: recent, nowEpochSeconds: nowSeconds,
                                settings: settings.rapidCrash
                            ) ?? RapidRiseDetector.detect(
                                symbol: symbol, bars: recent, nowEpochSeconds: nowSeconds,
                                settings: settings.rapidRise
                            ) ?? SustainedMoveDetector.detect(
                                symbol: symbol, bars: recent, nowEpochSeconds: nowSeconds,
                                settings: settings.sustainedMove
                            )
                            let saved: Bool
                            if let signal {
                                saved = try await signalStore.record(signal)
                            } else {
                                saved = false
                            }
                            return SymbolOutcome(received: bars.count, signalStored: saved, failure: nil)
                        } catch RadarSourceError.rateLimited {
                            return SymbolOutcome(received: 0, signalStored: false,
                                                 failure: "symbol=\(symbol) error=rateLimited",
                                                 rateLimited: true)
                        } catch RadarSourceError.invalidSymbol {
                            return SymbolOutcome(received: 0, signalStored: false,
                                                 failure: nil,
                                                 rejectedSymbol: symbol)
                        } catch {
                            return SymbolOutcome(
                                received: 0, signalStored: false,
                                failure: "symbol=\(symbol) error=\(String(describing: error))",
                                rateLimited: false
                            )
                        }
                    }
                }
                for await outcome in tasks {
                    yahooTotals.received += outcome.received
                    yahooTotals.valid += outcome.received
                    yahooTotals.operations += 1
                    if let failure = outcome.failure {
                        yahooTotals.errors += 1
                        yahooFailuresThisCycle += 1
                        if firstYahooFailure == nil { firstYahooFailure = failure }
                    }
                    if outcome.rateLimited { rateLimited = true }
                    if let symbol = outcome.rejectedSymbol {
                        unsupportedSymbols.insert(symbol)
                        rejectedSymbolsThisCycle += 1
                        if firstRejectedSymbol == nil { firstRejectedSymbol = symbol }
                    }
                    if outcome.signalStored { storedSignals += 1 }
                }
            }
            initialScanSymbols.formUnion(group)
            if rateLimited {
                yahooCooldownUntil = Date().addingTimeInterval(30 * 60)
                AppDiagnostics.shared.record(.warning, "Yahoo", "rate-limited",
                                             "cooldownMinutes=30")
                break
            }
        }
        if let firstYahooFailure {
            AppDiagnostics.shared.record(
                .warning, "Yahoo", "minute-bars-failed",
                "count=\(yahooFailuresThisCycle) first=\(firstYahooFailure)"
            )
        }
        if let firstRejectedSymbol {
            AppDiagnostics.shared.record(
                .info, "Yahoo", "unsupported-symbols-skipped",
                "count=\(rejectedSymbolsThisCycle) first=\(firstRejectedSymbol)"
            )
        }
        return MarketRadarCycle(
            yahoo: yahooTotals, traderFox: traderFoxTotals,
            yahooCooldownUntil: yahooCooldownUntil,
            initialScanProcessed: min(initialScanSymbols.count, initialScanTotal),
            initialScanTotal: initialScanTotal,
            scannedSymbols: symbols.count, storedSignals: storedSignals, companyNames: names
        )
    }

    private func refreshSources() async {
        nextDiscoveryAt = Date().addingTimeInterval(30 * 60)
        do {
            let symbols = try await yahoo.mostActiveCandidates()
            yahooTotals.operations += 1
            if !symbols.isEmpty {
                yahooCandidates = symbols
                unsupportedSymbols.removeAll()
                scanOffset = 0
            }
        } catch RadarSourceError.rateLimited {
            yahooTotals.operations += 1
            yahooTotals.errors += 1
            yahooCooldownUntil = Date().addingTimeInterval(30 * 60)
            AppDiagnostics.shared.record(.warning, "Yahoo", "candidate-rate-limited",
                                         "cooldownMinutes=30")
        } catch {
            yahooTotals.operations += 1
            yahooTotals.errors += 1
            AppDiagnostics.shared.record(
                .warning, "Yahoo", "candidate-refresh-failed",
                "error=\(String(describing: type(of: error)))"
            )
        }
        do {
            let symbols = try await traderFox.activeCandidates()
            traderFoxTotals.operations += 1
            traderFoxTotals.received += symbols.count
            traderFoxTotals.valid += symbols.count
            if !symbols.isEmpty { traderFoxCandidates = symbols }
        } catch {
            traderFoxTotals.operations += 1
            traderFoxTotals.errors += 1
            AppDiagnostics.shared.record(
                .warning, "TraderFox", "candidate-refresh-failed",
                "error=\(String(describing: type(of: error)))"
            )
        }
    }

    static func interleave(_ first: [String], _ second: [String], limit: Int) -> [String] {
        var result: [String] = []
        var seen = Set<String>()
        for index in 0..<max(first.count, second.count) {
            if index < first.count, seen.insert(first[index]).inserted { result.append(first[index]) }
            if index < second.count, seen.insert(second[index]).inserted { result.append(second[index]) }
            if result.count >= limit { break }
        }
        return Array(result.prefix(max(0, limit)))
    }

    static func scanSlice(_ symbols: [String], offset: Int, limit: Int) -> [String] {
        guard !symbols.isEmpty, limit > 0 else { return [] }
        return (0..<min(limit, symbols.count)).map { symbols[(offset + $0) % symbols.count] }
    }
}

private struct SymbolOutcome: Sendable {
    let received: Int
    let signalStored: Bool
    let failure: String?
    var rateLimited = false
    var rejectedSymbol: String? = nil
}
