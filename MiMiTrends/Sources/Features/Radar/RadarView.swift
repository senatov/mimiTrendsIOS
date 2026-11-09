import SwiftUI

struct RadarView: View {
    @Environment(RadarSession.self) private var session
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("radar.historyLimit.v1") private var maxResults = 30
    @AppStorage("radar.historyAgeHours.v1") private var maxAgeHours = 2
    @AppStorage("radar.scanWatchlist.v1") private var scanWatchlist = false
    @AppStorage("display.currency.v1") private var displayCurrency = "EUR"
    @Binding var symbol: String
    let watchlistRevision: Int
    let onManageWatchlist: () -> Void
    @State private var setupMessage: String?
    @State private var recentSignals: [ScanResult] = []
    @State private var showingSavedHistory = false
    @State private var hasLoadedHistory = false
    @State private var companyMetadata: [String: RadarCompanyMetadata] = [:]
    @State private var companyMetadataService = RadarCompanyMetadataService()
    @State private var selectedSignal: ScanResult?
    @State private var historyError: String?
    @State private var chartRefreshID = 0
    @State private var isPreparingFeed = false
    @State private var watchlistPreview: [WatchlistEntry] = []
    @State private var discoveryController = DiscoveryPoolController()
    @State private var lsCandidatePool = LSCandidatePool()
    @State private var lsStatus: LSCandidateStatus?
    @State private var marketScanner = MarketRadarScanner()
    @State private var signalBarBackfill = RadarSignalBarBackfill()
    @State private var marketCycle: MarketRadarCycle?
    @State private var currencyRates: DisplayCurrencyRates?
    @State private var currencyService = DisplayCurrencyService()
    @State private var discoveryStatus: DiscoveryRefreshStatus?
    @State private var discoveryRefreshID: UUID?
    @State private var discoveryRequests = 0
    @State private var discoveryErrors = 0
    @State private var showingSources = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                RadarWorkspace(
                    signals: { compact in signalList(compact: compact) },
                    sources: {
                        RadarSourcePanel(
                            session: session, discoveryStatus: discoveryStatus,
                            lsStatus: lsStatus,
                            discoveryRequests: discoveryRequests, discoveryErrors: discoveryErrors,
                            marketCycle: marketCycle
                        )
                    },
                    plot: {
                        RadarChartPreview(
                            symbol: chartSymbol,
                            companyName: chartCompanyName,
                            companyMetadata: companyMetadata[chartSymbol.uppercased()],
                            signal: selectedSignal,
                            currencyRates: currencyRates,
                            displayCurrency: displayCurrency,
                            refreshID: chartRefreshID
                        )
                    },
                    controls: {
                        RadarHeader(
                            symbol: $symbol, scanWatchlist: $scanWatchlist,
                            session: session, setupMessage: setupMessage,
                            isPreparingFeed: isPreparingFeed,
                            watchlist: watchlistPreview, onManageWatchlist: onManageWatchlist
                        ) {
                            if session.isScanning { session.stop() } else { startFeed() }
                        }
                    },
                    showingSources: $showingSources
                )
                .frame(maxHeight: .infinity)
            }
            .padding(8)
            .background(TrendsColors.canvas)
            .navigationTitle("Radar")
            .task(id: "\(maxResults)|\(maxAgeHours)") { await refreshSignals() }
            .task(id: companyMetadataRequestKey) { await refreshCompanyMetadata() }
            .task(id: scenePhase) { await refreshDiscoveryWhileActive() }
            .task(id: scenePhase) { await refreshLSWhileActive() }
            .task(id: scenePhase) { await scanMarketWhileActive() }
            .task(id: scenePhase) { await refreshDisplayCurrency() }
            .task { await detectInitialCurrency() }
            .task(id: "\(scenePhase)|\(watchlistRevision)") { await loadWatchlistPreview() }
            .onChange(of: scanWatchlist) { _, includeWatchlist in
                AppDiagnostics.shared.record(
                    .info, "Radar", "feed-scope-changed",
                    "scope=\(includeWatchlist ? "selected-and-watchlist" : "selected") appliesOnStart=true"
                )
                if includeWatchlist { Task { await loadWatchlistPreview() } }
            }
            .onChange(of: session.lastSignal) { _, latest in
                if latest != nil { Task { await refreshSignals(selectNewest: true) } }
            }
            .onChange(of: session.completedBarsStored) { _, _ in
                chartRefreshID += 1
            }
            .onChange(of: symbol) { _, newValue in
                if selectedSignal?.symbol != newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                    selectedSignal = nil
                }
            }
        }
    }

    private var radarCompanyNames: [String: String] {
        (marketCycle?.companyNames ?? [:]).merging(Dictionary((lsStatus?.quotes ?? []).map { ("LS:" + $0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first }), uniquingKeysWith: { first, _ in first })
    }
    private var chartSymbol: String {
        selectedSignal?.symbol ?? symbol
    }

    private var chartCompanyName: String {
        companyMetadata[chartSymbol.uppercased()]?.name ?? radarCompanyNames[chartSymbol] ?? chartSymbol
    }

    private var companyMetadataRequestKey: String {
        let symbols = Set(recentSignals.map(\.symbol))
        return chartSymbol.uppercased() + "|" + symbols.sorted().map { "\($0)=\(marketCycle?.companyNames[$0] ?? "")" }.joined(separator: "|")
    }

    private func refreshCompanyMetadata() async {
        let symbols = [chartSymbol] + recentSignals.map(\.symbol)
        companyMetadata = await companyMetadataService.cached(symbols: symbols)
        companyMetadata = await companyMetadataService.load(
            symbols: symbols, names: radarCompanyNames
        )
    }

    private func refreshDiscoveryWhileActive() async {
        guard scenePhase == .active else {
            discoveryRefreshID = nil
            await discoveryController.stop()
            return
        }
        var firstRefresh = true
        while !Task.isCancelled {
            let nowMillis = Int64(Date().timeIntervalSince1970 * 1_000)
            let isDue = firstRefresh || discoveryStatus.map { nowMillis >= $0.nextAttemptAtMillis } ?? true
            let refreshID = isDue ? UUID() : nil
            discoveryRefreshID = refreshID
            let status = await discoveryController.refresh()
            if discoveryRefreshID == refreshID { discoveryRefreshID = nil }
            guard !Task.isCancelled else { return }
            discoveryStatus = status
            if isDue {
                discoveryRequests += 1
                if !status.lastAttemptSucceeded { discoveryErrors += 1 }
                AppDiagnostics.shared.record(
                    status.lastAttemptSucceeded ? .info : .warning,
                    "Discovery", "refresh-finished",
                    "candidates=\(status.snapshot?.candidates.count ?? 0) success=\(status.lastAttemptSucceeded) nextAttemptMillis=\(status.nextAttemptAtMillis)"
                )
            }
            firstRefresh = false
            do { try await Task.sleep(for: .seconds(60)) }
            catch { return }
        }
    }

    private func refreshLSWhileActive() async {
        guard scenePhase == .active else {
            lsStatus = await lsCandidatePool.stop()
            return
        }
        while !Task.isCancelled {
            let status = await lsCandidatePool.refreshIfNeeded()
            guard !Task.isCancelled else { return }
            lsStatus = status
            if chartSymbol.hasPrefix("LS:") { chartRefreshID += 1 }
            await refreshSignals()
            do { try await Task.sleep(for: .seconds(30)) }
            catch { return }
        }
    }

    private func scanMarketWhileActive() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            do {
                let cycle = try await marketScanner.scan(settings: RadarScanPreferencesStore.load())
                guard !Task.isCancelled else { return }
                marketCycle = cycle
                await refreshSignals()
                AppDiagnostics.shared.record(
                    .info, "Radar", "market-scan-finished",
                    "symbols=\(cycle.scannedSymbols) initialScan=\(cycle.initialScanProcessed)/\(cycle.initialScanTotal) yahooErrors=\(cycle.yahoo.errors) candidateSource=\(cycle.usesFMP ? "FMP" : "TraderFox") candidateErrors=\(cycle.usesFMP ? cycle.fmp.errors : cycle.traderFox.errors)"
                )
            } catch is CancellationError {
                return
            } catch {
                AppDiagnostics.shared.record(
                    .error, "Radar", "market-scan-failed",
                    "error=\(String(describing: type(of: error)))"
                )
            }
            do { try await Task.sleep(for: .seconds(15)) }
            catch { return }
        }
    }

    private func refreshDisplayCurrency() async {
        guard scenePhase == .active else { return }
        currencyRates = await currencyService.cached()
        do { currencyRates = try await currencyService.latest() }
        catch { AppDiagnostics.shared.record(.warning, "ECB", "fx-rate-unavailable",
                                             "error=\(String(describing: type(of: error)))") }
    }

    private func detectInitialCurrency() async {
        guard !UserDefaults.standard.bool(forKey: "display.currency.initialized.v1") else { return }
        guard let detected = try? await IPLocationCurrencySource().detect(),
              !Task.isCancelled,
              !UserDefaults.standard.bool(forKey: "display.currency.initialized.v1") else { return }
        displayCurrency = detected.currency
        UserDefaults.standard.set(true, forKey: "display.currency.initialized.v1")
        AppDiagnostics.shared.record(.info, "Currency", "ip-country-detected",
                                     "country=\(detected.country) currency=\(detected.currency)")
    }

    private var currentActivity: RadarActivity? {
        if isPreparingFeed { return .preparingFeed }
        if session.isScanning && !session.isSubscribed {
            return .connectingFeed(symbolCount: session.targetSymbols.count)
        }
        if discoveryRefreshID != nil {
            return .loadingRankings(previousCount: discoveryStatus?.snapshot?.candidates.count)
        }
        return nil
    }

    private func signalList(compact: Bool) -> some View {
        RadarSignalList(
            signals: recentSignals,
            showingSavedHistory: showingSavedHistory,
            activity: recentSignals.isEmpty ? currentActivity : nil,
            companyNames: radarCompanyNames,
            companyMetadata: companyMetadata,
            currencyRates: currencyRates,
            displayCurrency: displayCurrency,
            selected: selectedSignal,
            compact: compact,
            errorMessage: historyError,
            sourcesOpen: showingSources,
            onToggleSources: { showingSources.toggle() },
            onSelect: { signal in
                selectedSignal = signal
                symbol = signal.symbol
            },
            onVisibleSignal: { visibleSymbol in
                if await signalBarBackfill.fillIfMissing(symbol: visibleSymbol) {
                    chartRefreshID += 1
                }
            },
            onRefresh: { Task { await refreshSignals() } }
        )
        .allowsHitTesting(!isHistoryLoading)
        .accessibilityHidden(isHistoryLoading)
        .overlay {
            if isHistoryLoading {
                RadarWarmupOverlay()
            }
        }
    }

    private var isHistoryLoading: Bool { !hasLoadedHistory }

    private func refreshSignals(selectNewest: Bool = false) async {
        defer { hasLoadedHistory = true }
        do {
            let limit = min(max(maxResults, 5), 100)
            let ageHours = min(max(maxAgeHours, 1), 72)
            let cutoff = Int64(Date().timeIntervalSince1970 * 1_000) - Int64(ageHours) * 3_600_000
            let preferences = RadarScanPreferencesStore.load()
            let allowSavedFallback = !hasLoadedHistory
            let (loaded, savedFallback) = try await Task.detached(priority: .userInitiated) {
                let store = try MarketSignalStore(url: MarketSignalStore.defaultURL())
                let history = try await store.loadRecent(limit: min(limit * 10, 500))
                return RadarSignalSelection.displayHistory(
                    history, since: cutoff, limit: limit, preferences: preferences,
                    allowSavedFallback: allowSavedFallback
                )
            }.value
            recentSignals = loaded
            showingSavedHistory = savedFallback
            AppDiagnostics.shared.record(.info, "Radar", "history-loaded", "signals=\(loaded.count)")
            historyError = nil
            if let selectedSignal, !loaded.contains(where: {
                $0.symbol == selectedSignal.symbol &&
                $0.signalSource == selectedSignal.signalSource &&
                $0.signalEpochMillis == selectedSignal.signalEpochMillis
            }) {
                self.selectedSignal = nil
            }
            if selectNewest, let latest = loaded.first {
                selectedSignal = latest
                symbol = latest.symbol
            } else if selectedSignal == nil {
                let requestedSymbol = symbol.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                selectedSignal = loaded.first { $0.symbol == requestedSymbol }
            }
        } catch {
            historyError = error.localizedDescription
            AppDiagnostics.shared.record(.error, "Radar", "history-failed", "error=\(String(describing: type(of: error)))")
        }
    }

    private func startFeed() {
        guard !isPreparingFeed else { return }
        isPreparingFeed = true
        AppDiagnostics.shared.record(.info, "Radar", "feed-preparing")
        Task { await prepareFeed() }
    }

    private func loadWatchlistPreview() async {
        do {
            watchlistPreview = try await Task.detached(priority: .utility) {
                let store = try WatchlistStore(url: WatchlistStore.defaultURL())
                return try await store.load()
            }.value
        } catch {
            AppDiagnostics.shared.record(
                .warning, "Radar", "watchlist-preview-failed",
                "error=\(String(describing: type(of: error)))"
            )
        }
    }

    @MainActor
    private func prepareFeed() async {
        defer { isPreparingFeed = false }
        setupMessage = nil
        do {
            let selected = symbol
            let includeWatchlist = scanWatchlist
            let watchlist: [WatchlistEntry]
            if includeWatchlist {
                watchlist = try await Task.detached(priority: .userInitiated) {
                    let store = try WatchlistStore(url: WatchlistStore.defaultURL())
                    return try await store.load()
                }.value
            } else {
                watchlist = []
            }
            guard scenePhase == .active else { return }
            let selection = try FinnhubWatchlistSelection(
                selectedSymbol: selected,
                includeWatchlist: includeWatchlist,
                watchlist: watchlist
            )
            watchlistPreview = watchlist
            AppDiagnostics.shared.record(
                .info, "Radar", "feed-scope-resolved",
                "scope=\(includeWatchlist ? "selected-and-watchlist" : "selected") watchlistEntries=\(watchlist.count) symbols=\(selection.symbols.joined(separator: ","))"
            )
            guard let key = try FinnhubCredentialStore.load() else {
                setupMessage = FinnhubStreamError.missingKey.localizedDescription
                AppDiagnostics.shared.record(.warning, "Radar", "feed-not-started", "reason=missing-api-key")
                return
            }
            guard scenePhase == .active else { return }
            let scanSettings = RadarScanPreferencesStore.load()
            session.start(symbols: selection.symbols) { [session, scanSettings] runID in
                do {
                    let pipeline = try FinnhubRadarPipeline(settings: scanSettings)
                    let bidAskSampler = FinnhubBidAskSampler()
                    try await FinnhubTradeStream().run(apiKey: key, symbols: selection.symbols) {
                        await session.markSubscribed(runID: runID)
                    } onTrade: { trade in
                        let nowEpochSeconds = Int64(Date().timeIntervalSince1970)
                        let quote = await bidAskSampler.latest(
                            symbol: trade.symbol, apiKey: key, nowMillis: nowEpochSeconds * 1_000
                        )
                        let update = try await pipeline.accept(
                            trade, nowEpochSeconds: nowEpochSeconds,
                            quote: quote, marketCurrency: "USD"
                        )
                        if update.storedBar {
                            await session.recordStoredBar(runID: runID)
                        }
                        if update.storedSignal, let signal = update.signal {
                            await session.recordSignal(signal, runID: runID)
                        }
                        await session.record(trade, runID: runID)
                    }
                } catch is CancellationError {
                    // The scene lifecycle or Stop button ended the feed.
                } catch {
                    await session.recordFailure(error.localizedDescription, runID: runID)
                }
            }
        } catch {
            setupMessage = error.localizedDescription
            AppDiagnostics.shared.record(.error, "Radar", "feed-setup-failed", "error=\(String(describing: type(of: error)))")
        }
    }
}
