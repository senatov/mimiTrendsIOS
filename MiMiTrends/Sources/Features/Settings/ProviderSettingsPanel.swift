import SwiftUI

struct ProviderSettingsPanel: View {
    @Environment(RadarSession.self) private var radarSession
    let width: CGFloat
    @State private var drafts: [ProviderEndpoint: String] = [:]
    @State private var checks: [ProviderEndpoint: String] = [:]
    @State private var savingMessage: String?

    private var columns: [GridItem] {
        width >= 980
            ? [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)]
            : [GridItem(.flexible(), alignment: .top)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider setup")
                        .font(SettingsTypography.sectionTitle)
                        .foregroundStyle(.indigo)
                    Text("Each provider's addresses, credentials and options are grouped together.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                TrendsActionButton(title: "Save URLs", systemImage: "checkmark") { save() }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                providerGroup(
                    "Finnhub",
                    detail: "Live US trade feed",
                    endpoints: [.finnhubTrades]
                )
                providerGroup(
                    "Yahoo Finance",
                    detail: "Candidates · minute + daily history · no API key",
                    endpoints: [.yahooPrimary, .yahooAlternate]
                )
                providerGroup(
                    "wallstreetONLINE rankings",
                    detail: "Wikifolio + Performance · shared base pool",
                    endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetOnline],
                    includesDiscoverySettings: true
                )
                providerGroup(
                    "Lang & Schwarz",
                    detail: "Fresh bid/ask movement signals · no trade volume",
                    endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope]
                )
                providerGroup(
                    "TraderFox",
                    detail: "Supplemental candidates when FMP is not configured",
                    endpoints: [.traderFox]
                )
                fmpGroup
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
        endpoints: [ProviderEndpoint],
        includesDiscoverySettings: Bool = false
    ) -> some View {
        SettingsGroup(title: title) {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("URLS CONFIGURED")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                    status: checks[endpoint] ?? defaultStatus(for: endpoint),
                    check: { check(endpoint) }
                )
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
                        radarSession.stop()
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
                    remove: { try FinnhubCredentialStore.deleteWebhookSecret() }
                )
            }
        }
    }

    private var fmpGroup: some View {
        SettingsGroup(title: "FMP") {
            Text("Optional candidate discovery, company profiles and fallback daily history. Uses FMP's stable API address; charts and the Finnhub feed work without this key.")
                .font(.callout)
                .foregroundStyle(.secondary)
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
                remove: { try ProviderCredentialStore.delete(FMPCredential.account) }
            )
        }
    }

    private func defaultStatus(for endpoint: ProviderEndpoint) -> String {
        endpoint == .finnhubTrades ? "Verified by the live feed" : "Not checked"
    }

    private func check(_ endpoint: ProviderEndpoint) {
        guard endpoint != .finnhubTrades else { return }
        let value = drafts[endpoint] ?? endpoint.defaultURL
        checks[endpoint] = "Checking…"
        Task {
            do {
                try await ProviderEndpointChecker().check(value, for: endpoint)
                guard drafts[endpoint] == value else { return }
                checks[endpoint] = "Address reachable"
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
        } catch {
            savingMessage = error.localizedDescription
        }
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
            HStack(spacing: 8) {
                TextField(endpoint.title, text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(SettingsTypography.url)
                    .foregroundStyle(SettingsColors.url)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(endpoint.title) URL")
                if endpoint != .finnhubTrades {
                    TrendsActionButton(title: "Check", systemImage: "checkmark.circle", action: check)
                }
            }
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
