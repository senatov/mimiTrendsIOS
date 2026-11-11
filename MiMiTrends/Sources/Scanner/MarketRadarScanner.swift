import Foundation

actor MarketRadarScanner {
    private var candidateStore: MarketBarStore?
    private let yahoo = YahooRadarSource()
    private let dax = BoerseDAXSource()
    private var previousSessions: RadarTradingSessions?
    private let traderFox = TraderFoxRadarSource()
    private let baselineSource = RadarBaselineSource()
    private var baselineCandidates: [RadarCompanyCandidate] = []
    private var yahooCandidates: [RadarCompanyCandidate] = []
    private var traderFoxCandidates: [RadarCompanyCandidate] = []
    private var germanCandidates: [RadarCompanyCandidate] = []
    private var discoveryPreferences = RadarDiscoveryPreferences.load()
    private var previousEnabledProviders: Set<MarketProvider>?
    private var nextDiscoveryAt: Date = .distantPast
    private var yahooCooldownUntil: Date?
    private var yahooTotals = RadarSourceTotals()
    private var traderFoxTotals = RadarSourceTotals()
    private var daxIssue: String?
    private var lastDAXQueueCount: Int?

    func scan(
        enabledProviders: Set<MarketProvider> = Set(MarketProvider.allCases)
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
            AppDiagnostics.shared.record(.info, "Discovery", "provider-selection-changed",
                "enabled=\(enabledProviders.map(\.rawValue).sorted().joined(separator: ",")) previous=\(previous?.map(\.rawValue).sorted().joined(separator: ",") ?? "initial") refresh=immediate")
        }
        let discovery = RadarDiscoveryPreferences.load()
        if discovery != discoveryPreferences {
            discoveryPreferences = discovery
            baselineCandidates = []
            nextDiscoveryAt = .distantPast
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
            traderFoxCandidates = sessions.us.isTrading && enabledProviders.contains(.traderFox)
                ? await restoreCandidates("traderFoxUS", fallback: traderFoxCandidates, store: store) : []
            germanCandidates = sessions.german.isTrading && enabledProviders.contains(.traderFox)
                ? await restoreCandidates("traderFoxDE", fallback: germanCandidates, store: store) : []
        }
        let refreshedDAX = try await refreshCandidatePool(
            sessions: sessions, enabledProviders: enabledProviders, baselineKey: baselineKey
        )
        return candidateCycle(daxCandidates: refreshedDAX.isEmpty ? cachedDAX : refreshedDAX)
    }

    private func refreshCandidatePool(
        sessions: RadarTradingSessions, enabledProviders: Set<MarketProvider>, baselineKey: String
    ) async throws -> [RadarCompanyCandidate] {
        let daxCandidates = enabledProviders.contains(.boerseDAX)
            ? try await dax.candidates(for: sessions, store: candidateStore) : []
        daxIssue = enabledProviders.contains(.boerseDAX) && sessions.german.isTrading
            ? MarketProviderAccess.lastError(.boerseDAX) : nil
        if Date() >= nextDiscoveryAt || sessions != previousSessions {
            try await refreshSources(enabledProviders: enabledProviders,
                                     sessions: sessions, baselineKey: baselineKey)
            previousSessions = sessions
        }
        return daxCandidates
    }

    private func candidateCycle(daxCandidates: [RadarCompanyCandidate]) -> MarketRadarCycle {
        let sessions = RadarTradingSessions(at: Date())
        let secondaryCandidates = traderFoxCandidates
        let activePool = RadarScanPool.symbols(
            baseline: baselineCandidates.map(\.symbol), yahoo: yahooCandidates.map(\.symbol),
            secondary: secondaryCandidates.map(\.symbol), german: (daxCandidates + germanCandidates).map(\.symbol),
            germanOpen: sessions.german.isTrading, usOpen: sessions.us.isTrading
        )
        let daxQueueCount = Set(daxCandidates.map(\.symbol)).intersection(activePool).count
        if daxQueueCount != lastDAXQueueCount {
            lastDAXQueueCount = daxQueueCount
            AppDiagnostics.shared.record(.info, "Radar", "dax-queue-updated",
                                         "inQueue=\(daxQueueCount) sourceCandidates=\(daxCandidates.count)")
        }
        let names = Dictionary(
            (daxCandidates + baselineCandidates + yahooCandidates + secondaryCandidates + germanCandidates)
                .map { ($0.symbol, $0.name) },
            uniquingKeysWith: { first, _ in first }
        )
        return MarketRadarCycle(
            yahoo: yahooTotals, traderFox: traderFoxTotals,
            yahooCooldownUntil: yahooCooldownUntil, initialScanProcessed: 0, initialScanTotal: 0,
            scannedSymbols: 0, companyNames: names,
            progress: MarketScanProgress(processed: 0, total: 0, successful: 0, skipped: 0,
                noRecentBars: 0, unsupported: 0, errors: 0,
                issues: [yahooTotals.lastErrorMessage, daxIssue].compactMap { $0 },
                activeSymbols: [], lastUpdatedAt: nil),
            candidates: activePool.map { RadarCompanyCandidate(symbol: $0, name: names[$0] ?? $0) }
        )
    }

    private func refreshSources(enabledProviders: Set<MarketProvider>,
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
        var traderFoxRefreshErrors: [String] = []
        if sessions.us.isTrading && enabledProviders.contains(.yahoo) && Date() >= (yahooCooldownUntil ?? .distantPast) {
          do {
            let symbols = try await yahoo.mostActiveCandidates(limit: 100)
            yahooTotals.operations += 1
            if !symbols.isEmpty {
                yahooCandidates = symbols
                await saveSnapshot(symbols, key: "yahoo")
                yahooTotals.received += symbols.count
                yahooTotals.valid += symbols.count
                yahooCooldownUntil = nil
                yahooTotals.lastErrorMessage = nil
                AppDiagnostics.shared.record(.info, "Yahoo", "candidate-page-loaded",
                                             "candidates=\(symbols.count) refreshMinutes=25")
            }
          } catch RadarSourceError.rateLimited {
            hadFailure = true
            yahooTotals.operations += 1
            yahooTotals.errors += 1
            yahooTotals.lastErrorMessage = "Yahoo temporarily limited requests (HTTP 429). Radar pauses Yahoo candidate requests for 30 minutes, then retries automatically."
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
        } else if !sessions.us.isTrading || !enabledProviders.contains(.yahoo) { yahooCandidates = [] }
        if sessions.us.isTrading && enabledProviders.contains(.traderFox) {
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
