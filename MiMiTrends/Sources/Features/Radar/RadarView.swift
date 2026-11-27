import SwiftUI

struct RadarView: View {
    @Environment(\.scenePhase) var scenePhase
    @AppStorage("radar.historyLimit.v1") private var maxResults = 30
    @AppStorage("radar.historyAgeHours.v1") private var maxAgeHours = 2
    @AppStorage("display.currency.v1") var displayCurrency = "EUR"
    @AppStorage("provider.configurationRevision.v1") var providerConfigurationRevision = 0
    @Binding var symbol: String
    let onManageWatchlist: () -> Void
    let onOpenProviderSettings: () -> Void
    @State var recentSignals: [ScanResult] = []
    @State var germanWatchCandidates: [ScanResult] = []
    @State var verifiedEIXSymbols: Set<String> = []
    @State private var hasLoadedHistory = false
    @State var companyMetadata: [String: RadarCompanyMetadata] = [:]
    @State var companyMetadataService = RadarCompanyMetadataService()
    @State private var selectedSignal: ScanResult?
    @State private var historyError: String?
    @State var chartRefreshID = 0
    @State var lsCandidatePool = LSCandidatePool()
    @State var lsStatus: LSCandidateStatus?
    @State var marketScanner = MarketRadarScanner()
    @State var marketCycle: MarketRadarCycle?
    @State var currencyRates: DisplayCurrencyRates?
    @State var currencyService = DisplayCurrencyService()
    @State var providerIssue: MarketProviderPreflightIssue?
    @State var providerStartupReady = false
    @AppStorage("radar.sources.open.v1") private var showingSources = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 6) {
                RadarWorkspace(
                    signals: { compact, width in signalList(compact: compact, width: width) },
                    sources: {
                        RadarSourcePanel(
                            lsStatus: lsStatus,
                            marketCycle: marketCycle
                        )
                    },
                    plot: {
                        RadarInstrumentChart(
                            symbol: chartSymbol,
                            companyName: chartCompanyName,
                            companyMetadata: companyMetadata[chartSymbol.uppercased()],
                            signal: selectedSignal,
                            currencyRates: currencyRates,
                            displayCurrency: displayCurrency,
                            refreshID: chartRefreshID,
                            providersReady: providerStartupReady,
                            yahooEnabled: MarketProviderAccess.isOperational(.yahoo),
                            providerRevision: providerConfigurationRevision
                        )
                    },
                    showingSources: $showingSources
                )
                .frame(maxHeight: .infinity)
            }
            .padding(8)
            .background(TrendsColors.canvas)
            #if os(iOS)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            #else
            .navigationTitle("Radar")
            #endif
            .toolbar {
                RadarHeader(symbol: $symbol, candidateCount: marketCycle?.candidates.count,
                            sourcesOpen: showingSources,
                            onToggleSources: { showingSources.toggle() },
                            onRefresh: { Task { await refreshSignals() } },
                            onManageWatchlist: onManageWatchlist)
            }
            .task(id: "\(scenePhase)|\(maxResults)|\(maxAgeHours)") { await refreshSignalHistoryWhileActive() }
            .task(id: "\(companyMetadataRequestKey)|\(providerConfigurationRevision)") {
                guard await ensureAutomaticProvidersReady() else { return }
                await refreshCompanyMetadata()
            }
            .task(id: "\(scenePhase)|\(providerConfigurationRevision)") { await refreshLSWhileActive() }
            .task(id: "\(scenePhase)|\(providerConfigurationRevision)") { await scanMarketWhileActive() }
            .task(id: "\(scenePhase)|\(providerConfigurationRevision)") { await refreshDisplayCurrency() }
            .task { await detectInitialCurrency() }
            .onChange(of: symbol) { _, newValue in
                if selectedSignal?.symbol != newValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                    selectedSignal = nil
                }
            }
            .onChange(of: providerConfigurationRevision) { _, _ in
                providerStartupReady = false
                providerIssue = nil
            }
            .sheet(item: $providerIssue) { issue in
                ProviderIssueSheet(
                    issue: issue,
                    openProviderSettings: {
                        providerIssue = nil
                        onOpenProviderSettings()
                    },
                    disableProvider: {
                        MarketProviderAccess.setEnabled(false, for: issue.provider)
                        providerIssue = nil
                    },
                    retry: { retryProvider(issue.provider) }
                )
            }
        }
    }

    var visibleSignals: [ScanResult] {
        RadarSignalSelection.withGermanReserve(
            recentSignals.filter {
                isEligibleSignal($0)
            },
            watch: germanWatchCandidates.filter { verifiedEIXSymbols.contains($0.symbol) },
            limit: min(max(maxResults, 5), 100)
        )
    }

    private func isEligibleSignal(_ signal: ScanResult) -> Bool {
        if marketCycle?.purchaseSymbols.contains(signal.symbol) == true { return true }
        return RadarSignalSelection.hasVerifiedOrigin(signal, currentSymbols: verifiedEIXSymbols)
    }

    func clearUnverifiedSelection() {
        if let selectedSignal,
           !isEligibleSignal(selectedSignal) {
            self.selectedSignal = nil
        }
    }

    var radarCompanyNames: [String: String] {
        (marketCycle?.companyNames ?? [:]).merging(Dictionary((lsStatus?.quotes ?? []).map { ("LS:" + $0.identifier, $0.name) }, uniquingKeysWith: { first, _ in first }), uniquingKeysWith: { first, _ in first })
    }
    var chartSymbol: String {
        selectedSignal?.symbol ?? symbol
    }

    private var chartCompanyName: String {
        let name = companyMetadata[chartSymbol.uppercased()]?.name ?? radarCompanyNames[chartSymbol] ?? chartSymbol
        return RadarSearchKeyword.cleanedCompanyName(name, symbol: chartSymbol)
    }

    var companyMetadataRequestKey: String {
        let symbols = Set(visibleSignals.map(\.symbol))
        return chartSymbol.uppercased() + "|" + symbols.sorted().map { "\($0)=\(marketCycle?.companyNames[$0] ?? "")" }.joined(separator: "|")
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

    private var emptyRadarMessage: String {
        "Waiting for fresh candle movements from Yahoo."
    }

    private func signalList(compact: Bool, width: CGFloat) -> some View {
        RadarSignalList(
            signals: visibleSignals,
            activity: nil,
            companyNames: radarCompanyNames,
            companyMetadata: companyMetadata,
            currencyRates: currencyRates,
            displayCurrency: displayCurrency,
            selected: selectedSignal,
            compact: compact,
            panelWidth: width,
            errorMessage: historyError,
            emptyStateMessage: emptyRadarMessage,
            onSelect: { signal in
                selectedSignal = signal.dataStatus == RadarGermanWatchCandidates.dataStatus ? nil : signal
                symbol = signal.symbol
            }
        )
        .allowsHitTesting(!isHistoryLoading)
        .accessibilityHidden(isHistoryLoading)
        .overlay {
            if isHistoryLoading {
                RadarWarmupOverlay()
            } else if marketCycle == nil {
                RadarActivityBanner(activity: .loadingRankings(previousCount: nil))
                    .padding()
                    .allowsHitTesting(false)
            }
        }
    }

    private var isHistoryLoading: Bool { !hasLoadedHistory }

    func refreshSignals(selectNewest: Bool = false) async {
        defer { hasLoadedHistory = true }
        do {
            let ageHours = min(max(maxAgeHours, 1), 72)
            let cutoff = Int64(Date().timeIntervalSince1970 * 1_000) - Int64(ageHours) * 3_600_000
            let preferences = RadarScanPreferencesStore.load()
            let germanSymbols = Set((marketCycle?.candidates ?? []).map(\.symbol).filter {
                verifiedEIXSymbols.contains($0) && MarketCandidateFilter.isGermanSymbol($0)
            })
            let (loaded, watch) = try await Task.detached(priority: .userInitiated) {
                let store = try MarketSignalStore(url: MarketSignalStore.defaultURL())
                let latest = try await store.loadRecent(limit: 500)
                let german = try await store.loadRecentGerman(limit: 100, sinceEpochMillis: cutoff)
                let history = latest + german
                var latestBars: [String: MinuteBar] = [:]
                if let barStore = try? MarketBarStore(url: MarketBarStore.defaultURL()) {
                    for signal in history where signal.signalEpochMillis >= cutoff {
                        if latestBars[signal.symbol] != nil { continue }
                        let bars = try? await barStore.loadRecentMinuteBars(
                            symbol: signal.symbol,
                            fromEpochSeconds: max(signal.signalEpochMillis / 1_000, Int64(Date().timeIntervalSince1970) - 600),
                            throughEpochSeconds: Int64(Date().timeIntervalSince1970), limit: 1
                        )
                        latestBars[signal.symbol] = bars?.last
                    }
                }
                let confirmed = RadarSignalSelection.displayHistory(
                    history, since: cutoff, limit: 600, preferences: preferences,
                    latestBars: latestBars
                )
                let watch = confirmed.contains(where: { germanSymbols.contains($0.symbol) }) ? []
                    : await RadarGermanWatchCandidates.load(symbols: germanSymbols, now: Date(),
                                                              settings: preferences.validated)
                return (confirmed, watch)
            }.value
            recentSignals = loaded
            germanWatchCandidates = watch
            let visible = visibleSignals
            let watchCount = visible.filter { $0.dataStatus == RadarGermanWatchCandidates.dataStatus }.count
            let germanCount = visible.filter { MarketCandidateFilter.isGermanSymbol($0.symbol) }.count
            AppDiagnostics.shared.record(.info, "Radar", "history-loaded",
                "signals=\(visible.count - watchCount) german=\(germanCount) watch=\(watchCount)")
            historyError = nil
            if let selectedSignal {
                self.selectedSignal = visible.first(where: {
                    $0.symbol == selectedSignal.symbol &&
                    $0.signalSource == selectedSignal.signalSource &&
                    $0.signalEpochMillis == selectedSignal.signalEpochMillis
                })
            }
            if selectNewest, let latest = visible.first(where: {
                $0.dataStatus != RadarGermanWatchCandidates.dataStatus
            }) {
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

}
