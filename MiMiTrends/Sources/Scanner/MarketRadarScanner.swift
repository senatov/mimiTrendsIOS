import Foundation

actor MarketRadarScanner {
    private var candidateStore: MarketBarStore?
    private let yahoo = YahooRadarSource()
    private let dax = BoerseDAXSource()
    private var previousSessions: RadarTradingSessions?
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
    private var daxIssue: String?
    private var lastDAXQueueCount: Int?

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
            baselineCandidates = []
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
        let sessions = RadarTradingSessions(at: Date())
        if candidateStore == nil {
            candidateStore = try? MarketBarStore(url: MarketBarStore.defaultURL())
        }
        let store = candidateStore
        let baselineKey = "baseline|\(discovery.wikifolio)|\(discovery.performance)|\(discovery.priority.rawValue)|\(discovery.endpointSignature)"
        let baselineUS = sessions.us.isTrading && enabledProviders.contains(.wallstreetOnline)
        let baselineDE = sessions.german == .regular && enabledProviders.contains(.wallstreetOnline)
        let useDAX = sessions.german.isTrading && enabledProviders.contains(.boerseDAX)
        var cachedDAX: [RadarCompanyCandidate] = []
        if useDAX {
            cachedDAX = (try? await store?.candidateSnapshot(source: "boerseDAX")) ?? []
            if cachedDAX.isEmpty { cachedDAX = await dax.currentCandidates }
        }
        if let store {
            let memoryUS = baselineCandidates.filter { !MarketCandidateFilter.isGermanSymbol($0.symbol) }
            let memoryDE = baselineCandidates.filter { MarketCandidateFilter.isGermanSymbol($0.symbol) }
            baselineCandidates = (baselineUS ? await restoreCandidates(baselineKey + "|US", fallback: memoryUS, store: store) : [])
                + (baselineDE ? await restoreCandidates(baselineKey + "|DE", fallback: memoryDE, store: store) : [])
            yahooCandidates = sessions.us.isTrading && enabledProviders.contains(.yahoo)
                ? await restoreCandidates("yahoo", fallback: yahooCandidates, store: store) : []
            fmpCandidates = sessions.us.isTrading && fmpKey != nil
                ? await restoreCandidates("fmp", fallback: fmpCandidates, store: store) : []
            traderFoxCandidates = sessions.us.isTrading && enabledProviders.contains(.traderFox) && fmpKey == nil
                ? await restoreCandidates("traderFoxUS", fallback: traderFoxCandidates, store: store) : []
            germanCandidates = sessions.german.isTrading && enabledProviders.contains(.traderFox)
                ? await restoreCandidates("traderFoxDE", fallback: germanCandidates, store: store) : []
        }
        let hasCachedPool = !(cachedDAX + baselineCandidates + yahooCandidates + fmpCandidates
            + traderFoxCandidates + germanCandidates).isEmpty
        if hasCachedPool {
            let cachedBaseline = baselineCandidates
            let cachedYahoo = yahooCandidates
            let cachedSecondary = fmpKey != nil ? fmpCandidates : traderFoxCandidates
            let cachedGerman = germanCandidates
            async let refresh = refreshCandidatePool(
                sessions: sessions, enabledProviders: enabledProviders, fmpKey: fmpKey, baselineKey: baselineKey
            )
            let result = try await scanCandidates(
                settings: settings, enabledProviders: enabledProviders, usesFMP: fmpKey != nil,
                daxCandidates: cachedDAX, baselineCandidates: cachedBaseline, yahooCandidates: cachedYahoo,
                secondaryCandidates: cachedSecondary, germanCandidates: cachedGerman, onProgress: onProgress
            )
            _ = try await refresh
            return result
        }
        let daxCandidates = try await refreshCandidatePool(
            sessions: sessions, enabledProviders: enabledProviders, fmpKey: fmpKey, baselineKey: baselineKey
        )
        return try await scanCandidates(
            settings: settings, enabledProviders: enabledProviders, usesFMP: fmpKey != nil,
            daxCandidates: daxCandidates, baselineCandidates: baselineCandidates, yahooCandidates: yahooCandidates,
            secondaryCandidates: fmpKey != nil ? fmpCandidates : traderFoxCandidates,
            germanCandidates: germanCandidates, onProgress: onProgress
        )
    }

    private func refreshCandidatePool(
        sessions: RadarTradingSessions, enabledProviders: Set<MarketProvider>, fmpKey: String?, baselineKey: String
    ) async throws -> [RadarCompanyCandidate] {
        let daxCandidates = enabledProviders.contains(.boerseDAX)
            ? try await dax.candidates(for: sessions, store: candidateStore) : []
        daxIssue = enabledProviders.contains(.boerseDAX) && sessions.german.isTrading
            ? MarketProviderAccess.lastError(.boerseDAX) : nil
        if Date() >= nextDiscoveryAt || sessions != previousSessions {
            try await refreshSources(fmpKey: fmpKey, enabledProviders: enabledProviders,
                                     sessions: sessions, baselineKey: baselineKey)
            previousSessions = sessions
        }
        return daxCandidates
    }

    private func scanCandidates(
        settings: RadarScanPreferences, enabledProviders: Set<MarketProvider>, usesFMP: Bool,
        daxCandidates: [RadarCompanyCandidate], baselineCandidates: [RadarCompanyCandidate],
        yahooCandidates: [RadarCompanyCandidate], secondaryCandidates: [RadarCompanyCandidate],
        germanCandidates: [RadarCompanyCandidate], onProgress: @Sendable (MarketScanProgress) async -> Void
    ) async throws -> MarketRadarCycle {
        try Task.checkCancellation()
        let currentSessions = RadarTradingSessions(at: Date())
        unreadableSymbols = await YahooSymbolResolutionStore.shared.skippedSymbols()
        let activePool = RadarScanPool.symbols(
            baseline: baselineCandidates.map(\.symbol), yahoo: yahooCandidates.map(\.symbol),
            secondary: secondaryCandidates.map(\.symbol), german: (daxCandidates + germanCandidates).map(\.symbol),
            germanOpen: currentSessions.german.isTrading, usOpen: currentSessions.us.isTrading,
            excluded: unsupportedSymbols.union(unreadableSymbols)
        )
        let daxQueueCount = Set(daxCandidates.map(\.symbol)).intersection(activePool).count
        if daxQueueCount != lastDAXQueueCount {
            lastDAXQueueCount = daxQueueCount
            AppDiagnostics.shared.record(.info, "Radar", "dax-queue-updated",
                                         "inQueue=\(daxQueueCount) sourceCandidates=\(daxCandidates.count)")
        }
        initialScanSymbols.formIntersection(activePool)
        initialScanTotal = activePool.count
        let names = Dictionary(
            (daxCandidates + baselineCandidates + yahooCandidates + secondaryCandidates + germanCandidates).map { ($0.symbol, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        func cycle(scanned: Int) -> MarketRadarCycle {
            MarketRadarCycle(yahoo: yahooTotals, traderFox: traderFoxTotals, fmp: fmpTotals, usesFMP: usesFMP,
                yahooCooldownUntil: yahooCooldownUntil, initialScanProcessed: initialScanSymbols.count,
                initialScanTotal: initialScanTotal, scannedSymbols: scanned, companyNames: names,
                progress: progress(),
                candidates: activePool.map { RadarCompanyCandidate(symbol: $0, name: names[$0] ?? $0) })
        }
        if let yahooCooldownUntil, Date() < yahooCooldownUntil { return cycle(scanned: 0) }
        yahooCooldownUntil = nil
        guard enabledProviders.contains(.yahoo) else { return cycle(scanned: 0) }
        let pending = activePool.filter { !initialScanSymbols.contains($0) }
        let symbols = Self.scanBatch(activePool, processed: initialScanSymbols, offset: scanOffset, limit: 16)
        if pending.isEmpty && !activePool.isEmpty {
            scanOffset = (scanOffset + symbols.count) % activePool.count
        }
        guard !symbols.isEmpty else { return cycle(scanned: 0) }
        let barStore = try candidateStore ?? MarketBarStore(url: MarketBarStore.defaultURL())
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
                        await RadarCandleScan.load(symbol: symbol, yahoo: yahoo, barStore: barStore,
                                                   nowSeconds: nowSeconds, settings: settings)
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
        return cycle(scanned: symbols.count)
    }

    private func progress(completedInBatch: Int = 0, activeSymbols: [String] = []) -> MarketScanProgress {
        MarketScanProgress(
            processed: min(initialScanSymbols.count + completedInBatch, initialScanTotal),
            total: initialScanTotal, successful: initialSuccessful,
            skipped: initialSkipped, noRecentBars: initialNoRecentBars,
            unsupported: initialUnsupported, errors: initialErrors,
            issues: [yahooTotals.lastErrorMessage, daxIssue].compactMap { $0 },
            activeSymbols: activeSymbols, lastUpdatedAt: lastUpdatedAt
        )
    }

    private func refreshSources(fmpKey: String?, enabledProviders: Set<MarketProvider>,
                                sessions: RadarTradingSessions, baselineKey: String) async throws {
        nextDiscoveryAt = Date().addingTimeInterval(RadarTradingSessions.refreshInterval)
        var hadFailure = false
        if (sessions.us.isTrading || sessions.german == .regular) &&
            enabledProviders.contains(.wallstreetOnline) && enabledProviders.contains(.yahoo) {
            do {
            let loaded = try await baselineSource.loadCandidates(sessions: sessions)
            if !loaded.isEmpty {
                let inactive = baselineCandidates.filter { candidate in
                    MarketCandidateFilter.isGermanSymbol(candidate.symbol)
                        ? sessions.german != .regular : !sessions.us.isTrading
                }
                baselineCandidates = loaded + inactive
                if sessions.us.isTrading {
                    await saveSnapshot(loaded.filter { !MarketCandidateFilter.isGermanSymbol($0.symbol) }, key: baselineKey + "|US")
                }
                if sessions.german == .regular {
                    await saveSnapshot(loaded.filter { MarketCandidateFilter.isGermanSymbol($0.symbol) }, key: baselineKey + "|DE")
                }
            }
            AppDiagnostics.shared.record(.info, "Discovery", "radar-baseline-loaded",
                                         "resolved=\(baselineCandidates.count)")
            } catch {
            if error is CancellationError { nextDiscoveryAt = .distantPast; throw error }
            hadFailure = true
            AppDiagnostics.shared.record(.warning, "Discovery", "radar-baseline-failed",
                                         "error=\(String(describing: error)) retrySeconds=60")
            }
        }
        var yahooRefreshed = false
        var traderFoxRefreshErrors: [String] = []
        if sessions.us.isTrading && enabledProviders.contains(.yahoo) {
          do {
            let symbols = try await yahoo.mostActiveCandidates(limit: 100)
            yahooTotals.operations += 1
            if !symbols.isEmpty {
                yahooCandidates = symbols
                await saveSnapshot(symbols, key: "yahoo")
                yahooTotals.received += symbols.count
                yahooTotals.valid += symbols.count
                yahooRefreshed = true
                yahooTotals.lastErrorMessage = nil
                unsupportedSymbols.removeAll()
                AppDiagnostics.shared.record(.info, "Yahoo", "candidate-page-loaded",
                                             "candidates=\(symbols.count) refreshMinutes=25")
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
        if let fmpKey, sessions.us.isTrading {
            do {
                let symbols = try await fmp.activeCandidates(apiKey: fmpKey, limit: 200)
                fmpTotals.operations += 3
                fmpTotals.received += symbols.count
                fmpTotals.valid += symbols.count
                fmpTotals.lastErrorMessage = nil
                fmpCandidates = symbols
                await saveSnapshot(symbols, key: "fmp")
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
        } else if sessions.us.isTrading && enabledProviders.contains(.traderFox) {
            do {
                let symbols = try await traderFox.activeCandidates(limit: 200)
                traderFoxTotals.operations += 1
                traderFoxTotals.received += symbols.count
                traderFoxTotals.valid += symbols.count
                if !symbols.isEmpty { traderFoxCandidates = symbols }
                await saveSnapshot(symbols, key: "traderFoxUS")
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
        if enabledProviders.contains(.traderFox) && sessions.german.isTrading {
          do {
            let symbols = try await traderFox.germanCandidates()
            traderFoxTotals.operations += 3
            traderFoxTotals.received += symbols.count
            traderFoxTotals.valid += symbols.count
            if !symbols.isEmpty { germanCandidates = symbols }
                await saveSnapshot(symbols, key: "traderFoxDE")
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
            if !enabledProviders.contains(.traderFox) { traderFoxCandidates = [] }
        }
        traderFoxTotals.lastErrorMessage = traderFoxRefreshErrors.isEmpty
            ? nil : traderFoxRefreshErrors.joined(separator: "\n")
        if hadFailure { nextDiscoveryAt = Date().addingTimeInterval(60) }
    }

    private func restoreCandidates(
        _ key: String, fallback: [RadarCompanyCandidate], store: MarketBarStore
    ) async -> [RadarCompanyCandidate] {
        do {
            let cached = try await store.candidateSnapshot(source: key)
            return cached.isEmpty ? fallback : cached
        } catch {
            AppDiagnostics.shared.record(.warning, "Discovery", "candidate-cache-read-failed", "error=\(String(describing: type(of: error)))")
            return fallback
        }
    }

    private func saveSnapshot(_ candidates: [RadarCompanyCandidate], key: String) async {
        guard !Task.isCancelled else { return }
        do { try await candidateStore?.saveCandidateSnapshot(candidates, source: key) }
        catch {
            AppDiagnostics.shared.record(.warning, "Discovery", "candidate-cache-write-failed",
                                         "error=\(String(describing: type(of: error)))")
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
