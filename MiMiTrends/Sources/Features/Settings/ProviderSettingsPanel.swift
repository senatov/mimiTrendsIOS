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
                        .font(.title3.weight(.light))
                    Text("These sources are used by Radar or the live trade feed.")
                        .font(.body.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
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
                    "Discovery",
                    detail: "Market ranking and linked instrument pages",
                    endpoints: [.wallstreetOnline, .traderFox]
                )
                endpointGroup(
                    "Lang & Schwarz",
                    detail: "Preliminary EUR quote observations",
                    endpoints: [.langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope]
                )
            }
            if let savingMessage {
                Label(savingMessage, systemImage: "checkmark.circle")
                    .font(.body.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
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
                Text("IN USE")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.green)
                Spacer()
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(TrendsColors.supportingInk)
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
            Text(endpoint.title).font(.body.weight(.regular))
            HStack(spacing: 8) {
                TextField(endpoint.title, text: $value)
                    .textFieldStyle(.roundedBorder)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .accessibilityLabel("\(endpoint.title) URL")
                if endpoint != .finnhubTrades {
                    Button("Check", action: check)
                        .buttonStyle(TrendsActionButtonStyle(compact: true))
                }
            }
            Text(status)
                .font(.subheadline.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
        }
    }
}
