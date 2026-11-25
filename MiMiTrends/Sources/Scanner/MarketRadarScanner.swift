import Foundation

actor MarketRadarScanner {
    private let yahoo = YahooRadarSource()
    private let tradingView = TradingViewVolatilitySource()
    private let eix = EIXInstrumentSource()
    private var candidateStore: RadarCandidateStore?
    private var germanCandidates: [RadarCompanyCandidate] = []
    private var usCandidates: [RadarCompanyCandidate] = []
    private var activeGermanCandidates: [RadarCompanyCandidate] = []
    private var activeUSCandidates: [RadarCompanyCandidate] = []
    private var strongGermanCandidates: [RadarCompanyCandidate] = []
    private var strongUSCandidates: [RadarCompanyCandidate] = []
    var watchlistStore: WatchlistStore?
    var dropCandidates: [RadarCompanyCandidate] = []
    var nextDropRefreshAt = Date.distantPast
    var reportedPriority: [String: String] = [:]
    private var eixISINs: Set<String> = []
    private var nextEIXRefreshAt: Date = .distantPast
    private var previousSessions: RadarTradingSessions?
    private var previousEnabledProviders: Set<MarketProvider>?
    private var endpointSignature = ""
    private var nextDiscoveryAt: Date = .distantPast
    private var tradingViewTotals = RadarSourceTotals()
    private var candleStore: MarketBarStore?
    private var candleOutcomes: [String: SymbolOutcome] = [:]
    private var candleCooldownUntil: Date?
    private var candleScanRound = 0
    private var nextScanRoundAt: Date = .distantPast
    private var lastCandleScanAt: [String: Date] = [:]

    func scan(enabledProviders: Set<MarketProvider> = Set(MarketProvider.allCases),
              retainedSymbols: [String] = []) async throws -> MarketRadarCycle {
        try Task.checkCancellation()
        let sessions = RadarTradingSessions(at: Date())
        let firstScan = candidateStore == nil
        if firstScan {
            candidateStore = try? RadarCandidateStore(directory: RadarCandidateStore.defaultDirectory())
        }
        if let candidateStore {
            await pruneCandidateCache(candidateStore)
            if firstScan {
                germanCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewDE")) ?? []
                usCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewUS")) ?? []
                activeGermanCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewActiveDE")) ?? []
                activeUSCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewActiveUS")) ?? []
                strongGermanCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewStrongDE")) ?? []
                strongUSCandidates = (try? await candidateStore.candidateSnapshot(source: "tradingViewStrongUS")) ?? []
                eixISINs = (try? await candidateStore.eixSnapshot()) ?? []
            }
        }
        if Date() >= nextEIXRefreshAt {
            nextEIXRefreshAt = Date().addingTimeInterval(60 * 60)
            do {
                eixISINs = try await eix.load()
                try? await candidateStore?.saveEIXSnapshot(eixISINs)
                AppDiagnostics.shared.record(.info, "EIX", "instruments-loaded",
                                             "isins=\(eixISINs.count)")
            } catch {
                nextEIXRefreshAt = Date().addingTimeInterval(5 * 60)
                AppDiagnostics.shared.record(.warning, "EIX", "instrument-refresh-failed",
                                             "error=\(String(reflecting: error)) cachedISINs=\(eixISINs.count)")
            }
        }
        let urls = ProviderEndpointStore.url(for: .tradingViewGermany).absoluteString + "|" +
            ProviderEndpointStore.url(for: .tradingViewUS).absoluteString
        if previousEnabledProviders != enabledProviders || endpointSignature != urls {
            previousEnabledProviders = enabledProviders
            endpointSignature = urls
            nextDiscoveryAt = .distantPast
            nextDropRefreshAt = .distantPast
        }
        if enabledProviders.contains(.tradingView),
           Date() >= nextDiscoveryAt || sessions != previousSessions {
            await refreshCandidates(sessions: sessions)
        }
        if enabledProviders.contains(.tradingView), enabledProviders.contains(.yahoo),
           Date() >= nextDropRefreshAt || sessions != previousSessions {
            await refreshDrops(sessions)
        }
        let watchlist = enabledProviders.contains(.yahoo) ? await loadWatchlist() : []
        previousSessions = sessions
        return candidateCycle(sessions: sessions, enabledProviders: enabledProviders,
                              retainedSymbols: retainedSymbols, watchlist: watchlist)
    }

    private func pruneCandidateCache(_ store: RadarCandidateStore) async {
        do {
            let removed = try await store.pruneExpiredSnapshots()
            if removed > 0 {
                AppDiagnostics.shared.record(.info, "Radar", "expired-candidate-snapshots-removed",
                                             "count=\(removed)")
            }
        } catch {
            AppDiagnostics.shared.record(.warning, "Radar", "candidate-cache-cleanup-failed",
                                         "error=\(String(reflecting: error))")
        }
    }

    private func refreshCandidates(sessions: RadarTradingSessions) async {
        nextDiscoveryAt = Date().addingTimeInterval(10 * 60)
        var failed = false
        for market in [TradingViewVolatilitySource.Market.germany, .unitedStates] {
            let active = market == .germany ? sessions.german == .regular : sessions.us.isTrading
            guard active else { continue }
            let activeKey = market == .germany ? "tradingViewActiveDE" : "tradingViewActiveUS"
            let strongKey = market == .germany ? "tradingViewStrongDE" : "tradingViewStrongUS"
            tradingViewTotals.operations += 1
            do {
                let loaded = try await tradingView.loadActive(market)
                let companies = loaded.map(\.company)
                if market == .germany { activeGermanCandidates = companies }
                else { activeUSCandidates = companies }
                tradingViewTotals.received += loaded.count
                tradingViewTotals.valid += loaded.count
                try? await candidateStore?.saveCandidateSnapshot(companies, source: activeKey)
                AppDiagnostics.shared.record(.info, "TradingView", "active-candidates-loaded",
                    "market=\(activeKey) selected=\(loaded.count) refreshMinutes=10")
            } catch {
                if Task.isCancelled { return }
                failed = true
                tradingViewTotals.errors += 1
                tradingViewTotals.lastErrorMessage =
                    MarketRadarErrorDescription.message(error, provider: "TradingView")
                AppDiagnostics.shared.record(.warning, "TradingView", "active-candidate-refresh-failed",
                    "market=\(market) error=\(String(describing: type(of: error)))")
            }
            let marketClock: RadarTradingMarket = market == .germany ? .germany : .unitedStates
            if Self.canScanStrongRisers(market: marketClock, at: Date()) {
                tradingViewTotals.operations += 1
                do {
                    let loaded = try await tradingView.loadStrongRisers(market)
                    let companies = loaded.map(\.company)
                    if market == .germany { strongGermanCandidates = companies }
                    else { strongUSCandidates = companies }
                    tradingViewTotals.received += loaded.count
                    tradingViewTotals.valid += loaded.count
                    try? await candidateStore?.saveCandidateSnapshot(companies, source: strongKey)
                    AppDiagnostics.shared.record(.info, "TradingView", "strong-risers-loaded",
                        "market=\(strongKey) selected=\(loaded.count) refreshMinutes=10")
                } catch {
                    if Task.isCancelled { return }
                    tradingViewTotals.errors += 1
                    AppDiagnostics.shared.record(.warning, "TradingView", "strong-risers-refresh-failed",
                        "market=\(strongKey) error=\(String(describing: type(of: error)))")
                }
            }
            tradingViewTotals.operations += 1
            do {
                let loaded = try await tradingView.load(market)
                let companies = loaded.map(\.company)
                if market == .germany { germanCandidates = companies }
                else { usCandidates = companies }
                tradingViewTotals.received += loaded.count
                tradingViewTotals.valid += loaded.count
                let key = market == .germany ? "tradingViewDE" : "tradingViewUS"
                try? await candidateStore?.saveCandidateSnapshot(companies, source: key)
                AppDiagnostics.shared.record(.info, "TradingView", "candidates-loaded",
                    "market=\(key) selected=\(loaded.count) refreshMinutes=10")
            } catch {
                if Task.isCancelled { return }
                failed = true
                tradingViewTotals.errors += 1
                tradingViewTotals.lastErrorMessage =
                    MarketRadarErrorDescription.message(error, provider: "TradingView")
                AppDiagnostics.shared.record(.warning, "TradingView", "candidate-refresh-failed",
                    "market=\(market) error=\(String(describing: type(of: error)))")
            }
        }
        if failed {
            MarketProviderAccess.setHealth("Needs attention", for: .tradingView,
                detail: tradingViewTotals.lastErrorMessage)
            nextDiscoveryAt = Date().addingTimeInterval(60)
        } else {
            tradingViewTotals.lastErrorMessage = nil
            if MarketProviderAccess.health(.tradingView) != "Connected" {
                MarketProviderAccess.setHealth("Connected", for: .tradingView)
            }
        }
    }

    private func candidateCycle(sessions: RadarTradingSessions,
                                enabledProviders: Set<MarketProvider>,
                                retainedSymbols: [String], watchlist: [String]) -> MarketRadarCycle {
        let enabled = enabledProviders.contains(.tradingView) && enabledProviders.contains(.yahoo)
        let eligibleUS = Self.eixCandidates(usCandidates, availableISINs: eixISINs)
        let eligibleGerman = Self.eixCandidates(germanCandidates, availableISINs: eixISINs)
        let activeUS = Self.eixCandidates(activeUSCandidates, availableISINs: eixISINs)
        let activeGerman = Self.eixCandidates(activeGermanCandidates, availableISINs: eixISINs)
        let now = Date()
        let strongUS = Self.canScanStrongRisers(market: .unitedStates, at: now)
            ? Self.eixCandidates(strongUSCandidates, availableISINs: eixISINs) : []
        let strongGerman = Self.canScanStrongRisers(market: .germany, at: now)
            ? Self.eixCandidates(strongGermanCandidates, availableISINs: eixISINs) : []
        let ranked = enabled ? RadarScanPool.prioritizedSymbols(
            activeUS: activeUS.map(\.symbol), activeGerman: activeGerman.map(\.symbol),
            strongUS: strongUS.map(\.symbol), strongGerman: strongGerman.map(\.symbol),
            volatileUS: eligibleUS.map(\.symbol), volatileGerman: eligibleGerman.map(\.symbol),
            germanOpen: sessions.german == .regular, usOpen: sessions.us.isTrading
        ) : []
        func isOpen(_ symbol: String) -> Bool {
            MarketCandidateFilter.supportsYahooBars(symbol: symbol) &&
                (MarketCandidateFilter.isGermanSymbol(symbol)
                    ? sessions.german == .regular : sessions.us.isTrading)
        }
        let retained = retainedSymbols.filter(isOpen)
        let drops = enabled ? Self.eixCandidates(dropCandidates, availableISINs: eixISINs)
            .map(\.symbol).filter(isOpen) : []
        let watched = watchlist.filter(isOpen)
        let pool = RadarScanPool.withRetainedSymbols(enabled ? retained : [], ranked: ranked,
                                                     watchlist: watched, drops: drops)
        logPriority(watchlist: watchlist, pool: pool, drops: enabled ? dropCandidates : [],
                    verified: verifiedEIXSymbols())

        let allCandidates = dropCandidates + strongUSCandidates + strongGermanCandidates +
            activeUSCandidates + activeGermanCandidates + usCandidates + germanCandidates
        let names = Dictionary(allCandidates.map { ($0.symbol, $0.name) },
                               uniquingKeysWith: { first, _ in first })
        return MarketRadarCycle(
            yahoo: RadarSourceTotals(), tradingView: tradingViewTotals,
            yahooCooldownUntil: candleCooldownUntil, initialScanProcessed: 0, initialScanTotal: 0,
            scannedSymbols: 0, companyNames: names,
            progress: MarketScanProgress(processed: 0, total: 0, successful: 0, skipped: 0,
                noRecentBars: 0, noReportedVolume: 0, unsupported: 0, errors: 0,
                issues: [tradingViewTotals.lastErrorMessage].compactMap { $0 },
                activeSymbols: [], lastUpdatedAt: nil),
            candidates: pool.map { RadarCompanyCandidate(symbol: $0, name: names[$0] ?? $0) },
            prioritySymbols: Array(drops.prefix(RadarScanPool.maximumShortDrops))
                .appendingUnique(watched).filter { pool.contains($0) }
        )
    }

    static func eixCandidates(_ candidates: [RadarCompanyCandidate],
                              availableISINs: Set<String>) -> [RadarCompanyCandidate] {
        candidates.filter { $0.isin.map(availableISINs.contains) ?? false }
    }

    static func canScanStrongRisers(market: RadarTradingMarket, at date: Date) -> Bool {
        if market.phase(at: date) == .afterHours { return true }
        guard market.phase(at: date) == .regular,
              let start = market.sessionStart(at: date) else { return false }
        return date.timeIntervalSince(start) >= 60 * 60
    }

    private var discoveredCompanies: [RadarCompanyCandidate] {
        dropCandidates + strongUSCandidates + strongGermanCandidates +
            activeUSCandidates + activeGermanCandidates + usCandidates + germanCandidates
    }

    func verifiedEIXSymbols() -> Set<String> {
        Set(Self.eixCandidates(discoveredCompanies, availableISINs: eixISINs).map(\.symbol))
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

    static func candleBatch(_ symbols: [String], processed: Set<String>, prioritySymbol: String?,
                            retainedSymbols: [String] = [], discoveryPriority: [String] = [],
                            lastScannedAt: [String: Date], now: Date) -> [String] {
        let selected = prioritySymbol?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let discovery = discoveryPriority.sorted {
            (lastScannedAt[$0] ?? .distantPast) < (lastScannedAt[$1] ?? .distantPast)
        }
        let preferred = ([selected].compactMap { $0 } + discovery + retainedSymbols.prefix(16) + symbols.prefix(3))
            .filter { symbols.contains($0) }
        var seen = Set<String>()
        let due = preferred.filter { seen.insert($0).inserted }
            .filter { now.timeIntervalSince(lastScannedAt[$0] ?? .distantPast) >= 60 }
        let priority = Array(due.prefix(8))
        let pending = symbols.filter { !processed.contains($0) && !priority.contains($0) }
        return priority + Array(pending.prefix(16 - priority.count))
    }

    func scanCandles(_ cycle: MarketRadarCycle, enabled: Bool,
                     prioritySymbol: String? = nil,
                     retainedSymbols: [String] = []) async -> (cycle: MarketRadarCycle, recordedSignal: Bool) {
        let symbols = cycle.candidates.map(\.symbol)
        candleOutcomes = candleOutcomes.filter { symbols.contains($0.key) }
        lastCandleScanAt = lastCandleScanAt.filter { symbols.contains($0.key) }
        guard enabled, !symbols.isEmpty else { return (cycle, false) }
        if candleOutcomes.count == symbols.count && Date() >= nextScanRoundAt {
            candleOutcomes.removeAll()
            candleScanRound += 1
            nextScanRoundAt = .distantPast
        }
        if candleStore == nil {
            do { candleStore = try MarketBarStore(url: MarketBarStore.defaultURL()) }
            catch {
                AppDiagnostics.shared.record(.error, "Radar", "candle-store-unavailable",
                    "error=\(String(describing: error))")
            }
        }
        guard let candleStore else { return (cycle, false) }
        let skipped = await YahooSymbolResolutionStore.shared.skippedSymbols()
        let diagnosticsSymbols = Set(cycle.prioritySymbols)
        let batch = Self.candleBatch(symbols, processed: Set(candleOutcomes.keys),
                                     prioritySymbol: prioritySymbol, retainedSymbols: retainedSymbols,
                                     discoveryPriority: cycle.prioritySymbols, lastScannedAt: lastCandleScanAt, now: Date())
        var recordedSignal = false
        if let cooldown = candleCooldownUntil, Date() >= cooldown { candleCooldownUntil = nil }
        if candleCooldownUntil == nil {
            let nowSeconds = Int64(Date().timeIntervalSince1970)
            let settings = RadarScanPreferencesStore.load()
            for start in stride(from: 0, to: batch.count, by: 4) {
                let chunk = Array(batch[start..<min(start + 4, batch.count)])
                let yahoo = self.yahoo
                let results = await withTaskGroup(of: SymbolOutcome.self, returning: [SymbolOutcome].self) { group in
                    for symbol in chunk {
                        group.addTask {
                            if skipped.contains(symbol) {
                                return SymbolOutcome(symbol: symbol, received: 0, failure: nil, skipped: true)
                            }
                            return await RadarCandleScan.load(symbol: symbol, yahoo: yahoo,
                                barStore: candleStore, nowSeconds: nowSeconds, settings: settings,
                                logNoSignal: diagnosticsSymbols.contains(symbol))
                        }
                    }
                    var outcomes: [SymbolOutcome] = []
                    for await outcome in group { outcomes.append(outcome) }
                    return outcomes
                }
                for outcome in results {
                    candleOutcomes[outcome.symbol] = outcome
                    lastCandleScanAt[outcome.symbol] = Date()
                    recordedSignal = recordedSignal || outcome.recordedSignal
                    if outcome.rateLimited {
                        candleCooldownUntil = Date().addingTimeInterval(30 * 60)
                    }
                }
                if candleCooldownUntil != nil { break }
            }
        }
        let values = Array(candleOutcomes.values)
        if values.count == symbols.count && nextScanRoundAt == .distantPast {
            nextScanRoundAt = Date().addingTimeInterval(120)
        }
        let successful = values.filter(\.usable).count
        if successful > 0, MarketProviderAccess.health(.yahoo) != "Connected" {
            MarketProviderAccess.setHealth("Connected", for: .yahoo)
        }
        let unsupported = values.filter { $0.rejectedSymbol != nil }.count
        let noRecent = values.filter { $0.skipped && $0.rejectedSymbol == nil && !$0.missingVolume }.count
        let noVolume = values.filter(\.missingVolume).count
        let errors = values.filter { $0.failure != nil }.count
        let issues = Array(Set(values.compactMap(\.failure))).sorted()
        let progress = MarketScanProgress(processed: values.count, total: symbols.count,
            successful: successful, skipped: values.filter(\.skipped).count,
            noRecentBars: noRecent, noReportedVolume: noVolume,
            unsupported: unsupported, errors: errors,
            issues: issues, activeSymbols: [], lastUpdatedAt: Date())
        AppDiagnostics.shared.record(.info, "Radar", "candle-scan-progress",
            "round=\(candleScanRound) checked=\(progress.processed)/\(progress.total) usable=\(successful) skipped=\(progress.skipped) noRecent=\(noRecent) noVolume=\(noVolume) unsupported=\(unsupported) errors=\(errors)")
        return (cycle.reporting(progress, cooldown: candleCooldownUntil ?? cycle.yahooCooldownUntil),
                recordedSignal)
    }
}
