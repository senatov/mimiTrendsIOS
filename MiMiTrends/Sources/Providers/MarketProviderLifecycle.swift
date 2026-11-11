import Foundation

enum MarketProvider: String, CaseIterable, Identifiable, Sendable {
    case yahoo, wallstreetOnline, langSchwarz, traderFox, boerseDAX

    var id: String { rawValue }
    var enabledKey: String { "provider.enabled.\(rawValue).v1" }
    var healthKey: String { "provider.health.\(rawValue).v1" }
    var errorKey: String { "provider.error.\(rawValue).v1" }

    var title: String {
        switch self {
        case .yahoo: "Yahoo Finance"
        case .wallstreetOnline: "wallstreetONLINE"
        case .langSchwarz: "Lang & Schwarz"
        case .traderFox: "TraderFox"
        case .boerseDAX: "boerse.de DAX"
        }
    }

    var accountURL: URL? {
        switch self {
        case .yahoo: URL(string: "https://finance.yahoo.com/")
        case .wallstreetOnline: URL(string: "https://www.wallstreet-online.de/")
        case .langSchwarz: URL(string: "https://www.ls-tc.de/")
        case .traderFox: URL(string: "https://www.traderfox.com/" )
        case .boerseDAX: URL(string: "https://www.boerse.de/realtime-kurse/Dax-Aktien/DE0008469008")
        }
    }

    var endpoints: [ProviderEndpoint] {
        switch self {
        case .yahoo: [.yahooPrimary, .yahooAlternate]
        case .wallstreetOnline: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance, .wallstreetOnline]
        case .langSchwarz: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope, .langSchwarzAmerica]
        case .traderFox: [.traderFox]
        case .boerseDAX: []
        }
    }
}

enum MarketProviderAccess {
    static func isEnabled(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: provider.enabledKey) != nil else { return true }
        return defaults.bool(forKey: provider.enabledKey)
    }

    static func setEnabled(_ enabled: Bool, for provider: MarketProvider, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: provider.enabledKey)
        defaults.set(enabled ? "Not checked" : "Disabled", forKey: provider.healthKey)
        defaults.removeObject(forKey: provider.errorKey)
        defaults.set(defaults.integer(forKey: "provider.configurationRevision.v1") + 1,
                     forKey: "provider.configurationRevision.v1")
    }

    static func health(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: provider.healthKey) ?? "Not checked"
    }

    static func lastError(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: provider.errorKey)
    }

    static func isOperational(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> Bool {
        isEnabled(provider, defaults: defaults) && health(provider, defaults: defaults) != "Needs attention"
    }

    static func setHealth(_ status: String, for provider: MarketProvider,
                          detail: String? = nil, defaults: UserDefaults = .standard) {
        defaults.set(status, forKey: provider.healthKey)
        if let detail { defaults.set(detail, forKey: provider.errorKey) }
        else { defaults.removeObject(forKey: provider.errorKey) }
        defaults.set(defaults.integer(forKey: "provider.healthRevision.v1") + 1,
                     forKey: "provider.healthRevision.v1")
    }
}

struct MarketProviderPreflightIssue: Identifiable, Sendable {
    let provider: MarketProvider
    let reason: String
    var id: String { provider.rawValue }
}

struct MarketProviderPreflight: Sendable {
    private let endpointChecker = ProviderEndpointChecker()

    func check(_ provider: MarketProvider) async -> MarketProviderPreflightIssue? {
        guard MarketProviderAccess.isEnabled(provider) else { return nil }
        do {
            switch provider {
            case .yahoo:
                try await requireAny([.yahooPrimary, .yahooAlternate])
            case .wallstreetOnline:
                try await requireWallstreetOnlineData()
            case .langSchwarz:
                do {
                    let quotes = try await LangSchwarzQuoteSource().loadQuotes()
                    guard !quotes.isEmpty else { throw MarketProviderPreflightError.unavailable }
                } catch LangSchwarzQuoteError.noFreshQuotes {
                    AppDiagnostics.shared.record(.info, "Lang & Schwarz", "preflight-no-fresh-quotes",
                        "lsQuoteSession=\(LangSchwarzMarketSession.isQuoteVenueOpen(at: Date()) ? "open" : "closed") underlyingOpen=\(LangSchwarzMarketSession.underlyingOpenEndpoints(at: Date()).map(\.rawValue).joined(separator: ",")) providerReachable=true")
                }
            case .traderFox:
                try await requireAll(provider.endpoints)
            case .boerseDAX:
                return nil // Checked by the scanner during German trading hours.
            }
            MarketProviderAccess.setHealth("Connected", for: provider)
            return nil
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let message = reason.isEmpty ? "Check the provider URL or availability." : reason
            MarketProviderAccess.setHealth("Needs attention", for: provider, detail: message)
            return MarketProviderPreflightIssue(provider: provider, reason: message)
        }
    }

    private func requireAll(_ endpoints: [ProviderEndpoint]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    _ = try await endpointChecker.check(
                        ProviderEndpointStore.url(for: endpoint).absoluteString, for: endpoint
                    )
                }
            }
            for try await _ in group {}
        }
    }

    private func requireWallstreetOnlineData() async throws {
        let preferences = RadarDiscoveryPreferences.load()
        let kinds = WallstreetRankingKind.allCases.filter {
            $0 == .wikifolio ? preferences.wikifolio : preferences.performance
        }
        let page = WallstreetRankingPageSource()
        for kind in kinds {
            if let entries = try? await page.load(kind), !entries.isEmpty { return }
        }
        if let entries = try? await page.loadGerman(), !entries.isEmpty { return }
        throw MarketProviderPreflightError.unavailable
    }

    private func requireAny(_ endpoints: [ProviderEndpoint]) async throws {
        var lastError: Error?
        for endpoint in endpoints {
            do {
                _ = try await endpointChecker.check(ProviderEndpointStore.url(for: endpoint).absoluteString, for: endpoint)
                return
            } catch { lastError = error }
        }
        throw lastError ?? MarketProviderPreflightError.unavailable
    }
}

actor MarketProviderStartupGate {
    static let shared = MarketProviderStartupGate()
    private var checkedRevision: Int?
    private var cachedIssues: [MarketProviderPreflightIssue] = []
    private var running: Task<[MarketProviderPreflightIssue], Never>?
    private var runningRevision: Int?

    func check(revision: Int) async -> [MarketProviderPreflightIssue] {
        if checkedRevision == revision { return cachedIssues }
        if let running {
            let result = await running.value
            if runningRevision == revision { return result }
            return await check(revision: revision)
        }
        let task = Task { [preflight = MarketProviderPreflight()] in
            let providers: [MarketProvider] = [.yahoo, .wallstreetOnline, .langSchwarz, .traderFox]
            return await withTaskGroup(of: MarketProviderPreflightIssue?.self) { group in
                for provider in providers {
                    group.addTask { await preflight.check(provider) }
                }
                var issues: [MarketProviderPreflightIssue] = []
                for await issue in group {
                    if let issue { issues.append(issue) }
                }
                return issues.sorted { $0.provider.rawValue < $1.provider.rawValue }
            }
        }
        running = task
        runningRevision = revision
        let issues = await task.value
        if runningRevision == revision {
            cachedIssues = issues
            checkedRevision = revision
        }
        running = nil
        runningRevision = nil
        return issues
    }

    func invalidate() {
        checkedRevision = nil
        cachedIssues = []
    }
}

private enum MarketProviderPreflightError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "The provider did not return the expected data. Check the URL or availability."
        }
    }
}
