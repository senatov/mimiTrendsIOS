import SwiftUI

struct ProviderSettingsPanel: View {
    @Environment(RadarSession.self) private var radarSession
    let width: CGFloat
    @State private var drafts: [ProviderEndpoint: String] = [:]
    @State private var checks: [ProviderEndpoint: String] = [:]
    @State private var savingMessage: String?
    @AppStorage("provider.configurationRevision.v1") private var providerConfigurationRevision = 0
    @AppStorage("provider.healthRevision.v1") private var providerHealthRevision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider setup")
                        .font(SettingsTypography.sectionTitle)
                        .foregroundStyle(.indigo)
                    Text("Each provider's addresses, credentials and options are grouped together.")
                        .font(.callout)
                        .foregroundStyle(.primary.opacity(0.72))
                }
                Spacer(minLength: 12)
                TrendsActionButton(title: "Save URLs", systemImage: "checkmark") { save() }
            }
            if width >= 980 {
                HStack(alignment: .top, spacing: 8) {
                    VStack(spacing: 6) {
                        providerGroup("Finnhub", detail: "Live US trade feed", provider: .finnhub, endpoints: [.finnhubTrades])
                        providerGroup("wallstreetONLINE rankings", detail: "Wikifolio + trading turnover · shared pool", provider: .wallstreetOnline,
                                      endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance, .wallstreetOnline], includesDiscoverySettings: true)
                        providerGroup("TraderFox", detail: "Supplemental candidates when FMP is not configured", provider: .traderFox, endpoints: [.traderFox])
                        providerGroup("boerse.de DAX", detail: "German DAX candidates · realtime page", provider: .boerseDAX, endpoints: [])
                    }
                    VStack(spacing: 6) {
                        providerGroup("Yahoo Finance", detail: "Most active + trending candidates · minute + daily history · no API key", provider: .yahoo, endpoints: [.yahooPrimary, .yahooAlternate])
                        providerGroup("Lang & Schwarz", detail: "Fresh bid/ask movement signals · Germany, Europe and America", provider: .langSchwarz,
                                      endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope])
                        fmpGroup
                    }
                }
            } else {
                VStack(spacing: 6) {
                    providerGroup("Finnhub", detail: "Live US trade feed", provider: .finnhub, endpoints: [.finnhubTrades])
                    providerGroup("Yahoo Finance", detail: "Most active + trending candidates · minute + daily history · no API key", provider: .yahoo, endpoints: [.yahooPrimary, .yahooAlternate])
                    providerGroup("wallstreetONLINE rankings", detail: "Wikifolio + trading turnover · shared pool", provider: .wallstreetOnline,
                                  endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance, .wallstreetOnline], includesDiscoverySettings: true)
                    providerGroup("Lang & Schwarz", detail: "Fresh bid/ask movement signals · Germany, Europe and America", provider: .langSchwarz,
                                  endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope])
                    providerGroup("TraderFox", detail: "Supplemental candidates when FMP is not configured", provider: .traderFox, endpoints: [.traderFox])
                    providerGroup("boerse.de DAX", detail: "German DAX candidates · realtime page", provider: .boerseDAX, endpoints: [])
                    fmpGroup
                }
            }
            if let savingMessage {
                Label(savingMessage, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            ProviderEndpointStore.removeUnusedLegacyValues()
            for endpoint in ProviderEndpoint.allCases {
                drafts[endpoint] = ProviderEndpointStore.url(for: endpoint).absoluteString
            }
        }
    }

    private func providerGroup(
        _ title: String,
        detail: String,
        provider: MarketProvider,
        endpoints: [ProviderEndpoint],
        includesDiscoverySettings: Bool = false
    ) -> some View {
        SettingsGroup(title: title, compact: true) {
            HStack(spacing: 6) {
                Circle().fill(providerIsHealthy(provider) ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(providerStatus(provider).uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(providerIsHealthy(provider) ? Color.primary.opacity(0.78) : Color.red)
                Spacer()
                Toggle("Enabled", isOn: enabledBinding(provider))
                    .labelsHidden()
                    .accessibilityLabel("Enable \(provider.title)")
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.72))
                    .multilineTextAlignment(.trailing)
            }
            ForEach(endpoints) { endpoint in
                ProviderEndpointRow(
                    endpoint: endpoint,
                    value: Binding(
                        get: { drafts[endpoint] ?? endpoint.defaultURL },
                        set: {
                            drafts[endpoint] = $0
                            checks[endpoint] = nil
                            savingMessage = nil
                        }
                    ),
                    status: checks[endpoint] ?? defaultStatus,
                    check: { check(endpoint) }
                )
            }
            if provider == .boerseDAX, let url = provider.accountURL {
                Link("Open DAX realtime quotes", destination: url).font(.caption)
                if let issue = MarketProviderAccess.lastError(provider) {
                    Text(issue).font(.caption).foregroundStyle(.secondary)
                }
            }
            if includesDiscoverySettings {
                DiscoverySettingsSection()
            }
            if endpoints.contains(.finnhubTrades) {
                CredentialEditor(
                    title: "Finnhub API key",
                    detail: "Required for the live trade feed and optional US bid/ask validation. Stored securely on this device.",
                    help: CredentialHelp(
                        title: "Get your Finnhub API key",
                        message: "Sign in to your Finnhub account and copy the API key from your account dashboard. Paste that key here. Account-plan permissions determine which symbols and endpoints are available.",
                        linkTitle: "Open Finnhub account",
                        url: URL(string: "https://finnhub.io/dashboard")
                    ),
                    load: { try FinnhubCredentialStore.load() },
                    save: { try FinnhubCredentialStore.save($0) },
                    remove: {
                        try FinnhubCredentialStore.delete()
                        credentialChanged(.finnhub)
                        checks[.finnhubTrades] = nil
                        radarSession.stop()
                    },
                    compact: true,
                    onSave: {
                        credentialChanged(.finnhub)
                        checks[.finnhubTrades] = nil
                    }
                )
                CredentialEditor(
                    title: "Finnhub webhook secret",
                    detail: "Not used by this app's live feed.",
                    help: CredentialHelp(
                        title: "Webhook secret is for your webhook server",
                        message: "This app does not receive Finnhub webhooks, so you can leave this blank. For a separate webhook integration, the server owner creates the shared secret and configures it on both the receiver and sender; it is not the Finnhub API key."
                    ),
                    load: { try FinnhubCredentialStore.loadWebhookSecret() },
                    save: { try FinnhubCredentialStore.saveWebhookSecret($0) },
                    remove: { try FinnhubCredentialStore.deleteWebhookSecret() },
                    compact: true
                )
            }
        }
    }

    private var fmpGroup: some View {
        SettingsGroup(title: "FMP", compact: true) {
            HStack(spacing: 6) {
                Circle().fill(providerIsHealthy(.fmp) ? Color.green : Color.red).frame(width: 8, height: 8)
                Text(providerStatus(.fmp).uppercased())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(providerIsHealthy(.fmp) ? Color.primary.opacity(0.78) : Color.red)
                Spacer()
                Toggle("Enabled", isOn: enabledBinding(.fmp))
                    .labelsHidden()
                    .accessibilityLabel("Enable Financial Modeling Prep")
            }
            Text("Optional candidate discovery, company profiles and fallback daily history. Uses FMP's stable API address; charts and the Finnhub feed work without this key.")
                .font(.callout)
                .foregroundStyle(.primary.opacity(0.72))
            if providerStatus(.fmp) == "Needs attention",
               let reason = MarketProviderAccess.lastError(.fmp) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CredentialEditor(
                title: "Financial Modeling Prep API key",
                detail: "Optional. FMP plan limits and endpoint access apply.",
                help: CredentialHelp(
                    title: "Get an FMP API key",
                    message: "Create an FMP account, verify your email, then copy the API key from your FMP dashboard. This key is optional and does not enable the Finnhub live feed. Free-plan access and limits depend on FMP's current plan terms.",
                    linkTitle: "Open FMP dashboard",
                    url: URL(string: "https://site.financialmodelingprep.com/developer/docs/dashboard")
                ),
                load: { try ProviderCredentialStore.load(FMPCredential.account) },
                save: { try ProviderCredentialStore.save($0, for: FMPCredential.account) },
                remove: {
                    try ProviderCredentialStore.delete(FMPCredential.account)
                    credentialChanged(.fmp)
                },
                compact: true,
                onSave: { credentialChanged(.fmp) }
            )
            Text("A missing or rejected key stops requests to this provider. Check your account and plan before enabling it.")
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.72))
        }
    }

    private var defaultStatus: String { "Not checked" }

    private func check(_ endpoint: ProviderEndpoint) {
        if endpoint == .finnhubTrades {
            guard MarketProviderAccess.isEnabled(.finnhub) else {
                checks[endpoint] = "Enable Finnhub before checking the live feed."
                return
            }
            checks[endpoint] = "Checking REST and WebSocket…"
            let value = drafts[endpoint] ?? endpoint.defaultURL
            Task {
                let restResult: String
                do {
                    guard let key = try FinnhubCredentialStore.load() else {
                        throw FinnhubStreamError.missingKey
                    }
                    try await FinnhubQuoteSmokeTest().check(symbol: "AAPL", apiKey: key)
                    restResult = "REST quote OK"
                    AppDiagnostics.shared.record(.info, "Finnhub", "quote-smoke-test-success", "symbol=AAPL")
                } catch {
                    restResult = "REST quote failed: \(error.localizedDescription)"
                    let nsError = error as NSError
                    AppDiagnostics.shared.record(.warning, "Finnhub", "quote-smoke-test-failed",
                        "errorType=\(String(describing: type(of: error))) domain=\(nsError.domain) code=\(nsError.code)")
                }
                let websocketResult: String
                if let issue = await MarketProviderPreflight().check(.finnhub, finnhubEndpoint: value) {
                    websocketResult = "WebSocket failed: \(issue.reason)"
                } else {
                    websocketResult = "WebSocket reachable; trades not confirmed"
                }
                guard drafts[endpoint] == value else { return }
                checks[endpoint] = "\(restResult) · \(websocketResult)"
            }
            return
        }
        let value = drafts[endpoint] ?? endpoint.defaultURL
        checks[endpoint] = "Checking…"
        Task {
            do {
                let result = try await ProviderEndpointChecker().check(value, for: endpoint)
                guard drafts[endpoint] == value else { return }
                checks[endpoint] = result
            } catch {
                guard drafts[endpoint] == value else { return }
                checks[endpoint] = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            for endpoint in ProviderEndpoint.allCases {
                _ = try ProviderEndpointStore.validate(drafts[endpoint] ?? endpoint.defaultURL, for: endpoint)
            }
            for endpoint in ProviderEndpoint.allCases {
                try ProviderEndpointStore.save(drafts[endpoint] ?? endpoint.defaultURL, for: endpoint)
            }
            savingMessage = "Addresses saved. Active adapters use them on the next request."
            UserDefaults.standard.set(
                UserDefaults.standard.integer(forKey: "provider.configurationRevision.v1") + 1,
                forKey: "provider.configurationRevision.v1"
            )
        } catch {
            savingMessage = error.localizedDescription
        }
    }

    private func enabledBinding(_ provider: MarketProvider) -> Binding<Bool> {
        Binding(
            get: { MarketProviderAccess.isEnabled(provider) },
            set: { enabled in
                MarketProviderAccess.setEnabled(enabled, for: provider)
                if !enabled, provider == .finnhub { radarSession.stop() }
            }
        )
    }

    private func providerStatus(_ provider: MarketProvider) -> String {
        _ = providerConfigurationRevision
        _ = providerHealthRevision
        return MarketProviderAccess.isEnabled(provider) ? MarketProviderAccess.health(provider) : "Disabled"
    }

    private func providerIsHealthy(_ provider: MarketProvider) -> Bool {
        MarketProviderAccess.isEnabled(provider) && MarketProviderAccess.health(provider) == "Connected"
    }

    private func credentialChanged(_ provider: MarketProvider) {
        MarketProviderAccess.setHealth("Not checked", for: provider)
        UserDefaults.standard.set(
            UserDefaults.standard.integer(forKey: "provider.configurationRevision.v1") + 1,
            forKey: "provider.configurationRevision.v1"
        )
    }
}

private struct ProviderEndpointRow: View {
    let endpoint: ProviderEndpoint
    @Binding var value: String
    let status: String
    let check: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(endpoint.title).font(SettingsTypography.label).foregroundStyle(.primary)
            HStack(spacing: 6) {
                TextField(endpoint.title, text: $value)
                    .settingsInputEmphasis()
                    .font(SettingsTypography.url)
                    .foregroundStyle(SettingsColors.url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(endpoint.title) URL")
                TrendsActionButton(title: "Check", systemImage: "checkmark.circle", action: check)
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.primary.opacity(0.72))
        }
    }
}
