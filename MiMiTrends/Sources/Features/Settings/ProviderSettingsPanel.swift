import SwiftUI

struct ProviderSettingsPanel: View {
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
                    Text("Active provider addresses")
                        .font(SettingsTypography.sectionTitle)
                        .foregroundStyle(.indigo)
                    Text("These sources are used by Radar or the live trade feed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                TrendsActionButton(title: "Save addresses", systemImage: "checkmark") { save() }
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                endpointGroup(
                    "Finnhub",
                    detail: "Live US trade feed",
                    endpoints: [.finnhubTrades]
                )
                endpointGroup(
                    "Yahoo Finance",
                    detail: "Active ticker candidates and minute candles",
                    endpoints: [.yahooPrimary, .yahooAlternate]
                )
                endpointGroup(
                    "wallstreetONLINE rankings",
                    detail: "Wikifolio + Performance · shared base pool",
                    endpoints: [.wallstreetWikifolio, .wallstreetPerformance, .wallstreetOnline]
                )
                endpointGroup(
                    "Lang & Schwarz",
                    detail: "Fresh bid/ask movement signals · no trade volume",
                    endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope]
                )
                endpointGroup("TraderFox", detail: "Supplemental candidates without an FMP key",
                              endpoints: [.traderFox])
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

    private func endpointGroup(
        _ title: String, detail: String, endpoints: [ProviderEndpoint]
    ) -> some View {
        SettingsGroup(title: title) {
            HStack(spacing: 8) {
                Circle().fill(Color.green).frame(width: 8, height: 8)
                Text("CONFIGURED")
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
