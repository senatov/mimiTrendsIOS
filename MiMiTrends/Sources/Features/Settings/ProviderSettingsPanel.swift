import SwiftUI

struct ProviderSettingsPanel: View {
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
                        providerGroup("wallstreetONLINE rankings", detail: "Wikifolio + trading turnover · shared pool", provider: .wallstreetOnline,
                                      endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance, .wallstreetOnline], includesDiscoverySettings: true)
                        providerGroup("TraderFox", detail: "Supplemental market candidates", provider: .traderFox, endpoints: [.traderFox])
                        providerGroup("boerse.de DAX", detail: "DAX and US-Tech 100 price monitoring · no volume", provider: .boerseDAX, endpoints: [])
                    }
                    VStack(spacing: 6) {
                        providerGroup("Yahoo Finance", detail: "Most active + trending candidates · no API key", provider: .yahoo, endpoints: [.yahooPrimary, .yahooAlternate])
                        providerGroup("Lang & Schwarz", detail: "Fresh bid/ask movement signals · Germany, Europe and America", provider: .langSchwarz,
                                      endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope])
                    }
                }
            } else {
                VStack(spacing: 6) {
                    providerGroup("Yahoo Finance", detail: "Most active + trending candidates · no API key", provider: .yahoo, endpoints: [.yahooPrimary, .yahooAlternate])
                    providerGroup("wallstreetONLINE rankings", detail: "Wikifolio + trading turnover · shared pool", provider: .wallstreetOnline,
                                  endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance, .wallstreetOnline], includesDiscoverySettings: true)
                    providerGroup("Lang & Schwarz", detail: "Fresh bid/ask movement signals · Germany, Europe and America", provider: .langSchwarz,
                                  endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope])
                    providerGroup("TraderFox", detail: "Supplemental market candidates", provider: .traderFox, endpoints: [.traderFox])
                    providerGroup("boerse.de DAX", detail: "DAX and US-Tech 100 price monitoring · no volume", provider: .boerseDAX, endpoints: [])
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
        }
    }

    private var defaultStatus: String { "Not checked" }

    private func check(_ endpoint: ProviderEndpoint) {
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
