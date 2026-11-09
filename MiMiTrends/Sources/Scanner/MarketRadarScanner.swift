import Foundation

actor MarketRadarScanner {
    private let yahoo = YahooRadarSource()
    private let traderFox = TraderFoxRadarSource()
    private let fmp = FMPCandidateSource()
    private let baselineSource = RadarBaselineSource()
    private var baselineCandidates: [RadarCompanyCandidate] = []
    private var yahooCandidates: [RadarCompanyCandidate] = []
    private var traderFoxCandidates: [RadarCompanyCandidate] = []
    private var germanCandidates: [RadarCompanyCandidate] = []
    private var fmpCandidates: [RadarCompanyCandidate] = []
    private var discoveryPreferences = RadarDiscoveryPreferences.load()
    private var previousEnabledProviders: Set<MarketProvider>?
    private var activeFMPKey: String?
    private var nextDiscoveryAt: Date = .distantPast
    private var yahooCooldownUntil: Date?
    private var unsupportedSymbols = Set<String>()
    private var unreadableSymbols = Set<String>()
    private var scanOffset = 0
    private var initialScanSymbols = Set<String>()
    private var initialScanTotal = 0
    private var yahooTotals = RadarSourceTotals()
    private var traderFoxTotals = RadarSourceTotals()
    private var fmpTotals = RadarSourceTotals()
    private var initialSuccessful = 0
    private var initialSkipped = 0
    private var initialNoRecentBars = 0
    private var initialUnsupported = 0
    private var initialErrors = 0
    private var lastUpdatedAt: Date?

    func scan(
        settings: RadarScanPreferences,
        enabledProviders: Set<MarketProvider> = Set(MarketProvider.allCases),
        onProgress: @Sendable (MarketScanProgress) async -> Void = { _ in }
    ) async throws -> MarketRadarCycle {
        try Task.checkCancellation()
        if previousEnabledProviders != enabledProviders {
            let previous = previousEnabledProviders
            previousEnabledProviders = enabledProviders
            nextDiscoveryAt = .distantPast
            if !enabledProviders.contains(.wallstreetOnline) { baselineCandidates = [] }
            if !enabledProviders.contains(.yahoo) { yahooCandidates = [] }
            if !enabledProviders.contains(.traderFox) {
                traderFoxCandidates = []
                germanCandidates = []
            }
            if !enabledProviders.contains(.fmp) { fmpCandidates = [] }
            initialScanSymbols = []
            initialScanTotal = 0
            initialSuccessful = 0
            initialSkipped = 0
            initialNoRecentBars = 0
            initialUnsupported = 0
            initialErrors = 0
            AppDiagnostics.shared.record(.info, "Discovery", "provider-selection-changed",
                "enabled=\(enabledProviders.map(\.rawValue).sorted().joined(separator: ",")) previous=\(previous?.map(\.rawValue).sorted().joined(separator: ",") ?? "initial") refresh=immediate")
        }
        let discovery = RadarDiscoveryPreferences.load()
        if discovery != discoveryPreferences {
            discoveryPreferences = discovery
            nextDiscoveryAt = .distantPast
        }
        let fmpKey = enabledProviders.contains(.fmp)
            ? try? ProviderCredentialStore.load(FMPCredential.account) : nil
        if fmpKey != activeFMPKey {
            activeFMPKey = fmpKey
            fmpCandidates = []
            nextDiscoveryAt = .distantPast
            initialScanSymbols = []
            initialScanTotal = 0
            initialSuccessful = 0
            initialSkipped = 0
            initialNoRecentBars = 0
            initialUnsupported = 0
            initialErrors = 0
        }
        let usesFMP = fmpKey != nil
        if Date() >= nextDiscoveryAt {
            try await refreshSources(fmpKey: fmpKey, enabledProviders: enabledProviders)
        }
        let secondaryCandidates = usesFMP ? fmpCandidates : traderFoxCandidates
        let secondaryUS = secondaryCandidates.filter { !MarketCandidateFilter.isGermanSymbol($0.symbol) }
        let secondaryGerman = secondaryCandidates.filter { MarketCandidateFilter.isGermanSymbol($0.symbol) }
        let usSymbols = Self.interleave(yahooCandidates.map(\.symbol), secondaryUS.map(\.symbol), limit: 80)
        let germanSymbols = (germanCandidates + secondaryGerman).map(\.symbol)
        let supplemental = Self.interleave(usSymbols, germanSymbols, limit: 160)
        let pool = Self.interleave(baselineCandidates.map(\.symbol), [], limit: 2_000)
            .appendingUnique(supplemental)
            .filter { !unsupportedSymbols.contains($0) }
        let activePool = pool.filter {
            (!MarketCandidateFilter.isGermanSymbol($0) || GermanMarketSession.isOpen(at: Date()))
                && !unreadableSymbols.contains($0)
        }
        initialScanTotal = activePool.count
        let names = Dictionary(
            (baselineCandidates + yahooCandidates + secondaryCandidates + germanCandidates).map { ($0.symbol, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        if let yahooCooldownUntil, Date() < yahooCooldownUntil {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    fmp: fmpTotals, usesFMP: usesFMP,
                                    yahooCooldownUntil: yahooCooldownUntil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, companyNames: names,
                                    progress: progress())
        }
        yahooCooldownUntil = nil
        guard enabledProviders.contains(.yahoo) else {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    fmp: fmpTotals, usesFMP: usesFMP,
                                    yahooCooldownUntil: nil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, companyNames: names,
                                    progress: progress())
        }
        let pending = activePool.filter { !initialScanSymbols.contains($0) }
        let symbols = Self.scanBatch(activePool, processed: initialScanSymbols, offset: scanOffset, limit: 16)
        if pending.isEmpty && !activePool.isEmpty {
            scanOffset = (scanOffset + symbols.count) % activePool.count
        }
        guard !symbols.isEmpty else {
            return MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals,
                                    fmp: fmpTotals, usesFMP: usesFMP,
                                    yahooCooldownUntil: nil,
                                    initialScanProcessed: initialScanSymbols.count,
                                    initialScanTotal: initialScanTotal,
                                    scannedSymbols: 0, companyNames: names,
                                    progress: progress())
        }
        let barStore = try MarketBarStore(url: MarketBarStore.defaultURL())
        let nowSeconds = Int64(Date().timeIntervalSince1970)
        var firstYahooFailure: String?
        var yahooFailuresThisCycle = 0
        var rejectedSymbolsThisCycle = 0
        var firstRejectedSymbol: String?
        var unreadableSymbolsThisCycle: [String] = []
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
                            let evaluationTime = RadarMarketDataPolicy.evaluationTime(symbol: symbol, now: nowSeconds)
                            guard let last = bars.last,
                                  last.minuteEpochSeconds <= nowSeconds + 60,
                                  last.minuteEpochSeconds >= evaluationTime - 600 else {
                                RadarMarketDataPolicy.logStale(symbol: symbol, bars: bars, now: nowSeconds)
                                return SymbolOutcome(symbol: symbol, received: bars.count,
                                                     failure: nil, skipped: true)
                            }
                            for bar in bars { _ = try await barStore.upsert(bar) }
                            RadarMarketDataPolicy.logAccepted(symbol: symbol, bars: bars, now: nowSeconds)
                            return SymbolOutcome(symbol: symbol, received: bars.count, failure: nil)
                        } catch RadarSourceError.rateLimited {
                            return SymbolOutcome(symbol: symbol, received: 0,
                                                 failure: "Yahoo temporarily limited requests (HTTP 429). Radar pauses scanning for 30 minutes, then retries automatically.",
                                                 rateLimited: true)
                        } catch RadarSourceError.invalidSymbol {
                            return SymbolOutcome(symbol: symbol, received: 0,
                                                 failure: nil,
                                                 rejectedSymbol: symbol, skipped: true)
                        } catch {
                            let unreadableSymbol: String?
                            if let radarError = error as? RadarSourceError,
                               case .invalidResponse = radarError {
                                unreadableSymbol = symbol
                            } else {
                                unreadableSymbol = nil
                            }
                            return SymbolOutcome(
                                symbol: symbol, received: 0,
                                failure: MarketRadarErrorDescription.message(error, provider: "Yahoo (\(symbol))"),
                                rateLimited: false,
                                unreadableSymbol: unreadableSymbol
                            )
                        }
                    }
                }
                for await outcome in tasks {
                    active.removeAll { $0 == outcome.symbol }
                    completed += 1
                    yahooTotals.received += outcome.received
                    if !outcome.skipped { yahooTotals.valid += outcome.received }
                    yahooTotals.operations += 1
                    if let failure = outcome.failure {
                        yahooTotals.errors += 1
                        yahooTotals.lastErrorMessage = failure
                        yahooFailuresThisCycle += 1
                        if firstYahooFailure == nil { firstYahooFailure = failure }
                    }
                    if outcome.rateLimited { rateLimited = true }
                    if let symbol = outcome.rejectedSymbol {
                        unsupportedSymbols.insert(symbol)
                        rejectedSymbolsThisCycle += 1
                        if firstRejectedSymbol == nil { firstRejectedSymbol = symbol }
                    }
                    if let symbol = outcome.unreadableSymbol {
                        unreadableSymbols.insert(symbol)
                        unreadableSymbolsThisCycle.append(symbol)
                    }
                    if !initialScanSymbols.contains(outcome.symbol) {
                        if outcome.failure != nil { initialErrors += 1 }
                        else if outcome.skipped {
                            initialSkipped += 1
                            if outcome.rejectedSymbol != nil { initialUnsupported += 1 }
                            else { initialNoRecentBars += 1 }
                        }
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
        if !unreadableSymbolsThisCycle.isEmpty {
            AppDiagnostics.shared.record(.warning, "Yahoo", "unreadable-symbols-paused",
                "count=\(unreadableSymbolsThisCycle.count) first=\(unreadableSymbolsThisCycle[0]) resumeAfterCandidateRefresh=true")
        }
        return MarketRadarCycle(
            yahoo: yahooTotals, traderFox: traderFoxTotals, fmp: fmpTotals, usesFMP: usesFMP,
            yahooCooldownUntil: yahooCooldownUntil,
            initialScanProcessed: min(initialScanSymbols.count, initialScanTotal),
            initialScanTotal: initialScanTotal,
            scannedSymbols: symbols.count, companyNames: names,
            progress: progress()
        )
    }

    private func progress(completedInBatch: Int = 0, activeSymbols: [String] = []) -> MarketScanProgress {
        MarketScanProgress(
            processed: min(initialScanSymbols.count + completedInBatch, initialScanTotal),
            total: initialScanTotal, successful: initialSuccessful,
            skipped: initialSkipped, noRecentBars: initialNoRecentBars,
            unsupported: initialUnsupported, errors: initialErrors,
            activeSymbols: activeSymbols, lastUpdatedAt: lastUpdatedAt
        )
    }

    private func refreshSources(fmpKey: String?, enabledProviders: Set<MarketProvider>) async throws {
        nextDiscoveryAt = Date().addingTimeInterval(30 * 60)
        var hadFailure = false
        if enabledProviders.contains(.wallstreetOnline) && enabledProviders.contains(.yahoo) {
            do {
            let loaded = try await baselineSource.loadCandidates()
            if !loaded.isEmpty { baselineCandidates = loaded }
            AppDiagnostics.shared.record(.info, "Discovery", "radar-baseline-loaded",
                                         "resolved=\(baselineCandidates.count)")
            } catch {
            if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
            hadFailure = true
            AppDiagnostics.shared.record(.warning, "Discovery", "radar-baseline-failed",
                                         "error=\(String(describing: error)) retrySeconds=60")
            }
        } else {
            baselineCandidates = []
        }
        var yahooRefreshed = false
        var traderFoxRefreshErrors: [String] = []
        if enabledProviders.contains(.yahoo) {
          do {
            let symbols = try await yahoo.mostActiveCandidates()
            yahooTotals.operations += 1
            if !symbols.isEmpty {
                yahooCandidates = symbols
                yahooRefreshed = true
                yahooTotals.lastErrorMessage = nil
                unsupportedSymbols.removeAll()
                unreadableSymbols.removeAll()
                scanOffset = 0
            }
          } catch RadarSourceError.rateLimited {
            hadFailure = true
            yahooTotals.operations += 1
            yahooTotals.errors += 1
            yahooTotals.lastErrorMessage = "Yahoo temporarily limited requests (HTTP 429). Radar pauses Yahoo scanning for 30 minutes, then retries automatically."
            yahooCooldownUntil = Date().addingTimeInterval(30 * 60)
            AppDiagnostics.shared.record(.warning, "Yahoo", "candidate-rate-limited",
                                         "cooldownMinutes=30")
          } catch {
            if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
            hadFailure = true
            yahooTotals.operations += 1
            yahooTotals.errors += 1
            yahooTotals.lastErrorMessage = MarketRadarErrorDescription.message(error, provider: "Yahoo")
            AppDiagnostics.shared.record(
                .warning, "Yahoo", "candidate-refresh-failed",
                "error=\(MarketRadarErrorDescription.message(error, provider: "Yahoo candidate discovery"))"
            )
          }
        } else { yahooCandidates = [] }
        if let fmpKey {
            do {
                let symbols = try await fmp.activeCandidates(apiKey: fmpKey)
                fmpTotals.operations += 3
                fmpTotals.received += symbols.count
                fmpTotals.valid += symbols.count
                fmpTotals.lastErrorMessage = nil
                fmpCandidates = symbols
                let yahooSet = Set(yahooCandidates.map(\.symbol))
                let overlap = symbols.filter { yahooSet.contains($0.symbol) }.count
                AppDiagnostics.shared.record(
                    .info, "FMP", "candidate-comparison",
                    "fmp=\(symbols.count) yahoo=\(yahooCandidates.count) yahooFresh=\(yahooRefreshed) overlap=\(overlap) sourceTimestamp=unavailable"
                )
            } catch is CancellationError {
                nextDiscoveryAt = .distantPast
                throw CancellationError()
            } catch let failure as FMPCandidateFailure {
                hadFailure = true
                fmpTotals.operations += failure.requests
                fmpTotals.errors += 1
                fmpTotals.lastErrorMessage = failure.localizedDescription
                AppDiagnostics.shared.record(
                    .warning, "FMP", "candidate-refresh-failed",
                    "requests=\(failure.requests) endpoint=\(failure.endpoint) error=\(failure.reason)"
                )
            } catch {
                if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
                hadFailure = true
                fmpTotals.errors += 1
                fmpTotals.lastErrorMessage = MarketRadarErrorDescription.message(error, provider: "FMP")
                AppDiagnostics.shared.record(
                    .warning, "FMP", "candidate-refresh-failed",
                    "error=\(String(describing: type(of: error)))"
                )
            }
        } else if enabledProviders.contains(.traderFox) {
            do {
                let symbols = try await traderFox.activeCandidates()
                traderFoxTotals.operations += 1
                traderFoxTotals.received += symbols.count
                traderFoxTotals.valid += symbols.count
                if !symbols.isEmpty { traderFoxCandidates = symbols }
            } catch {
                if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
                hadFailure = true
                traderFoxTotals.operations += 1
                traderFoxTotals.errors += 1
                traderFoxTotals.lastErrorMessage = MarketRadarErrorDescription.message(error, provider: "TraderFox US candidates")
                traderFoxRefreshErrors.append(traderFoxTotals.lastErrorMessage ?? "TraderFox request failed.")
                AppDiagnostics.shared.record(
                    .warning, "TraderFox", "candidate-refresh-failed",
                    "error=\(String(describing: type(of: error)))"
                )
            }
        }
        if enabledProviders.contains(.traderFox) {
          do {
            let symbols = try await traderFox.germanCandidates()
            traderFoxTotals.operations += 3
            traderFoxTotals.received += symbols.count
            traderFoxTotals.valid += symbols.count
            if !symbols.isEmpty { germanCandidates = symbols }
          } catch {
            if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
            hadFailure = true
            traderFoxTotals.operations += 3
            traderFoxTotals.errors += 1
            traderFoxTotals.lastErrorMessage = MarketRadarErrorDescription.message(error, provider: "TraderFox German candidates")
            traderFoxRefreshErrors.append(traderFoxTotals.lastErrorMessage ?? "TraderFox request failed.")
            AppDiagnostics.shared.record(
                .warning, "TraderFox", "german-candidate-refresh-failed",
                "error=\(String(describing: type(of: error)))"
            )
          }
        } else {
            germanCandidates = []
            traderFoxCandidates = []
        }
        traderFoxTotals.lastErrorMessage = traderFoxRefreshErrors.isEmpty
            ? nil : traderFoxRefreshErrors.joined(separator: "\n")
        if hadFailure { nextDiscoveryAt = Date().addingTimeInterval(60) }
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
    let failure: String?
    var rateLimited = false
    var rejectedSymbol: String? = nil
    var unreadableSymbol: String? = nil
    var skipped = false
}
