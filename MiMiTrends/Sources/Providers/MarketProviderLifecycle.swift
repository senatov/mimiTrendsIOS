import Foundation

enum MarketProvider: String, CaseIterable, Identifiable, Sendable {
    case finnhub, yahoo, wallstreetOnline, langSchwarz, traderFox, fmp

    var id: String { rawValue }
    var enabledKey: String { "provider.enabled.\(rawValue).v1" }
    var healthKey: String { "provider.health.\(rawValue).v1" }

    var title: String {
        switch self {
        case .finnhub: "Finnhub"
        case .yahoo: "Yahoo Finance"
        case .wallstreetOnline: "wallstreetONLINE"
        case .langSchwarz: "Lang & Schwarz"
        case .traderFox: "TraderFox"
        case .fmp: "Financial Modeling Prep"
        }
    }

    var accountURL: URL? {
        switch self {
        case .finnhub: URL(string: "https://finnhub.io/dashboard")
        case .yahoo: URL(string: "https://finance.yahoo.com/")
        case .wallstreetOnline: URL(string: "https://www.wallstreet-online.de/")
        case .langSchwarz: URL(string: "https://www.ls-tc.de/")
        case .traderFox: URL(string: "https://www.traderfox.com/" )
        case .fmp: URL(string: "https://site.financialmodelingprep.com/developer/docs/dashboard")
        }
    }

    var endpoints: [ProviderEndpoint] {
        switch self {
        case .finnhub: [.finnhubTrades]
        case .yahoo: [.yahooPrimary, .yahooAlternate]
        case .wallstreetOnline: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetOnline]
        case .langSchwarz: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope]
        case .traderFox: [.traderFox]
        case .fmp: []
        }
    }
}

enum MarketProviderAccess {
    static func isEnabled(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: provider.enabledKey) != nil else {
            switch provider {
            case .fmp:
                return (try? ProviderCredentialStore.load(FMPCredential.account)) != nil
            case .finnhub:
                return (try? FinnhubCredentialStore.load()) != nil
            default:
                break
            }
            return true
        }
        return defaults.bool(forKey: provider.enabledKey)
    }

    static func setEnabled(_ enabled: Bool, for provider: MarketProvider, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: provider.enabledKey)
        defaults.set(enabled ? "Not checked" : "Disabled", forKey: provider.healthKey)
        defaults.set(defaults.integer(forKey: "provider.configurationRevision.v1") + 1,
                     forKey: "provider.configurationRevision.v1")
    }

    static func health(_ provider: MarketProvider, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: provider.healthKey) ?? "Not checked"
    }

    static func setHealth(_ status: String, for provider: MarketProvider, defaults: UserDefaults = .standard) {
        defaults.set(status, forKey: provider.healthKey)
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
            case .finnhub:
                guard let key = try FinnhubCredentialStore.load() else {
                    throw MarketProviderPreflightError.missingCredential("Finnhub API key")
                }
                _ = try FinnhubTradeStream.streamURL(apiKey: key)
                _ = try await FinnhubBidAskClient().load(symbol: "AAPL", apiKey: key)
            case .yahoo:
                try await requireAny([.yahooPrimary, .yahooAlternate])
            case .wallstreetOnline:
                try await requireAll(provider.endpoints)
            case .langSchwarz:
                try await requireAll(provider.endpoints)
            case .traderFox:
                try await requireAll(provider.endpoints)
            case .fmp:
                guard let key = try ProviderCredentialStore.load(FMPCredential.account) else {
                    throw MarketProviderPreflightError.missingCredential("FMP API key")
                }
                try await FMPCandidateSource().check(apiKey: key)
            }
            MarketProviderAccess.setHealth("Connected", for: provider)
            return nil
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            let message = reason.isEmpty ? "Check the provider URL, account access, or API key." : reason
            MarketProviderAccess.setHealth("Needs attention", for: provider)
            return MarketProviderPreflightIssue(provider: provider, reason: message)
        }
    }

    private func requireAll(_ endpoints: [ProviderEndpoint]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for endpoint in endpoints {
                group.addTask {
                    try await endpointChecker.check(
                        ProviderEndpointStore.url(for: endpoint).absoluteString, for: endpoint
                    )
                }
            }
            for try await _ in group {}
        }
    }

    private func requireAny(_ endpoints: [ProviderEndpoint]) async throws {
        var lastError: Error?
        for endpoint in endpoints {
            do {
                try await endpointChecker.check(ProviderEndpointStore.url(for: endpoint).absoluteString, for: endpoint)
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
            let providers: [MarketProvider] = [.yahoo, .wallstreetOnline, .langSchwarz, .traderFox, .finnhub, .fmp]
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
    case missingCredential(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .missingCredential(let name): "\(name) is missing. Add it in provider settings."
        case .unavailable: "The provider did not return the expected data. Check the URL, account access, or API key."
        }
    }
}
