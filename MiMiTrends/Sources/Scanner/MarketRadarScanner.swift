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
    let fmp: RadarSourceTotals
    let usesFMP: Bool
    let yahooCooldownUntil: Date?
    let initialScanProcessed: Int
    let initialScanTotal: Int
    let scannedSymbols: Int
    let storedSignals: Int
    let companyNames: [String: String]
    let progress: MarketScanProgress
}

struct MarketScanProgress: Sendable, Equatable {
    let processed: Int
    let total: Int
    let successful: Int
    let skipped: Int
    let errors: Int
    let activeSymbols: [String]
    let lastUpdatedAt: Date?
}

actor MarketRadarScanner {
    private let yahoo = YahooRadarSource()
    private let traderFox = TraderFoxRadarSource()
    private let fmp = FMPCandidateSource()
    private var yahooCandidates: [RadarCompanyCandidate] = []
    private var traderFoxCandidates: [RadarCompanyCandidate] = []
    private var fmpCandidates: [RadarCompanyCandidate] = []
    private var activeFMPKey: String?
    private var nextDiscoveryAt: Date = .distantPast
    private var yahooCooldownUntil: Date?
    private var unsupportedSymbols = Set<String>()
    private var scanOffset = 0
    private var initialScanSymbols = Set<String>()
    private var initialScanTotal = 0
    private var yahooTotals = RadarSourceTotals()
    private var traderFoxTotals = RadarSourceTotals()
    private var fmpTotals = RadarSourceTotals()
    private var initialSuccessful = 0
    private var initialSkipped = 0
    private var initialErrors = 0
    private var lastUpdatedAt: Date?

    func scan(
        settings: RadarScanPreferences,
        onProgress: @Sendable (MarketScanProgress) async -> Void = { _ in }
    ) async throws -> MarketRadarCycle {
        try Task.checkCancellation()
        let fmpKey = try? ProviderCredentialStore.load(FMPCredential.account)
        if fmpKey != activeFMPKey {
            activeFMPKey = fmpKey
            fmpCandidates = []
            nextDiscoveryAt = .distantPast
            initialScanSymbols = []
            initialScanTotal = 0
            initialSuccessful = 0
            initialSkipped = 0
            initialErrors = 0
        }
        let usesFMP = fmpKey != nil
        if Date() >= nextDiscoveryAt {
            await refreshSources(fmpKey: fmpKey)
        }
        let secondaryCandidates = usesFMP ? fmpCandidates : traderFoxCandidates
        let pool = Self.interleave(yahooCandidates.map(\.symbol), secondaryCandidates.map(\.symbol), limit: 16)
            .filter { !unsupportedSymbols.contains($0) }
        if initialScanTotal == 0 { initialScanTotal = pool.count }
        let names = Dictionary(
            (yahooCandidates + secondaryCandidates).map { ($0.symbol, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        if let yahooCooldownUntil, Date() < yahooCooldownUntil {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    fmp: fmpTotals, usesFMP: usesFMP,
                                    yahooCooldownUntil: yahooCooldownUntil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, storedSignals: 0, companyNames: names,
                                    progress: progress())
        }
        yahooCooldownUntil = nil
        let pending = pool.filter { !initialScanSymbols.contains($0) }
        let symbols = Self.scanBatch(pool, processed: initialScanSymbols, offset: scanOffset, limit: 4)
        if pending.isEmpty && !pool.isEmpty {
            scanOffset = (scanOffset + symbols.count) % pool.count
        }
        guard !symbols.isEmpty else {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    fmp: fmpTotals, usesFMP: usesFMP,
                                    yahooCooldownUntil: nil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, storedSignals: 0, companyNames: names,
                                    progress: progress())
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
            var active = group
            var completed = 0
            await onProgress(progress(activeSymbols: active))
            await withTaskGroup(of: SymbolOutcome.self) { tasks in
                for symbol in group {
                    tasks.addTask { [yahoo] in
                        do {
                            let bars = try await yahoo.minuteBars(symbol: symbol)
                            try Task.checkCancellation()
                            guard let last = bars.last,
                                  last.minuteEpochSeconds >= nowSeconds - 600 else {
                                return SymbolOutcome(symbol: symbol, received: bars.count,
                                                     signalStored: false, failure: nil, skipped: true)
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
                            return SymbolOutcome(symbol: symbol, received: bars.count,
                                                 signalStored: saved, failure: nil)
                        } catch RadarSourceError.rateLimited {
                            return SymbolOutcome(symbol: symbol, received: 0, signalStored: false,
                                                 failure: "symbol=\(symbol) error=rateLimited",
                                                 rateLimited: true)
                        } catch RadarSourceError.invalidSymbol {
                            return SymbolOutcome(symbol: symbol, received: 0, signalStored: false,
                                                 failure: nil,
                                                 rejectedSymbol: symbol, skipped: true)
                        } catch {
                            return SymbolOutcome(
                                symbol: symbol, received: 0, signalStored: false,
                                failure: "symbol=\(symbol) error=\(String(describing: error))",
                                rateLimited: false
                            )
                        }
                    }
                }
                for await outcome in tasks {
                    active.removeAll { $0 == outcome.symbol }
                    completed += 1
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
                    if !initialScanSymbols.contains(outcome.symbol) {
                        if outcome.failure != nil { initialErrors += 1 }
                        else if outcome.skipped { initialSkipped += 1 }
                        else { initialSuccessful += 1 }
                    }
                    await onProgress(progress(completedInBatch: completed, activeSymbols: active))
                }
            }
            initialScanSymbols.formUnion(group)
            lastUpdatedAt = Date()
            await onProgress(progress())
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
            yahoo: yahooTotals, traderFox: traderFoxTotals, fmp: fmpTotals, usesFMP: usesFMP,
            yahooCooldownUntil: yahooCooldownUntil,
            initialScanProcessed: min(initialScanSymbols.count, initialScanTotal),
            initialScanTotal: initialScanTotal,
            scannedSymbols: symbols.count, storedSignals: storedSignals, companyNames: names,
            progress: progress()
        )
    }

    private func progress(completedInBatch: Int = 0, activeSymbols: [String] = []) -> MarketScanProgress {
        MarketScanProgress(
            processed: min(initialScanSymbols.count + completedInBatch, initialScanTotal),
            total: initialScanTotal, successful: initialSuccessful,
            skipped: initialSkipped, errors: initialErrors,
            activeSymbols: activeSymbols, lastUpdatedAt: lastUpdatedAt
        )
    }

    private func refreshSources(fmpKey: String?) async {
        nextDiscoveryAt = Date().addingTimeInterval(30 * 60)
        var yahooRefreshed = false
        do {
            let symbols = try await yahoo.mostActiveCandidates()
            yahooTotals.operations += 1
            if !symbols.isEmpty {
                yahooCandidates = symbols
                yahooRefreshed = true
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
        if let fmpKey {
            do {
                let symbols = try await fmp.activeCandidates(apiKey: fmpKey)
                fmpTotals.operations += 3
                fmpTotals.received += symbols.count
                fmpTotals.valid += symbols.count
                fmpCandidates = symbols
                let yahooSet = Set(yahooCandidates.map(\.symbol))
                let overlap = symbols.filter { yahooSet.contains($0.symbol) }.count
                AppDiagnostics.shared.record(
                    .info, "FMP", "candidate-comparison",
                    "fmp=\(symbols.count) yahoo=\(yahooCandidates.count) yahooFresh=\(yahooRefreshed) overlap=\(overlap) sourceTimestamp=unavailable"
                )
            } catch let failure as FMPCandidateFailure {
                fmpTotals.operations += failure.requests
                fmpTotals.errors += 1
                AppDiagnostics.shared.record(
                    .warning, "FMP", "candidate-refresh-failed",
                    "requests=\(failure.requests) error=\(failure.reason)"
                )
            } catch {
                fmpTotals.errors += 1
                AppDiagnostics.shared.record(
                    .warning, "FMP", "candidate-refresh-failed",
                    "error=\(String(describing: type(of: error)))"
                )
            }
        } else {
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

    static func scanBatch(_ symbols: [String], processed: Set<String>, offset: Int, limit: Int) -> [String] {
        let pending = symbols.filter { !processed.contains($0) }
        return pending.isEmpty ? scanSlice(symbols, offset: offset, limit: limit)
            : Array(pending.prefix(max(0, limit)))
    }
}

private struct SymbolOutcome: Sendable {
    let symbol: String
    let received: Int
    let signalStored: Bool
    let failure: String?
    var rateLimited = false
    var rejectedSymbol: String? = nil
    var skipped = false
}
