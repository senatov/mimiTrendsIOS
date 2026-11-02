import SwiftUI

struct ProviderSettingsPanel: View {
    @State private var drafts: [ProviderEndpoint: String] = [:]
    @State private var checks: [ProviderEndpoint: String] = [:]
    @State private var savingMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("Provider addresses")
                    .font(.title3.weight(.light))
                Spacer()
                TrendsActionButton(
                    title: "Save addresses",
                    systemImage: "checkmark"
                ) { save() }
            }
            Text(
                "Check an address before saving. A reachable page does not mean its quote adapter is active."
            )
            .font(.body.weight(.light))
            .foregroundStyle(TrendsColors.supportingInk)
            if let savingMessage {
                Text(savingMessage)
                    .font(.body.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
            }
            group("Finnhub", endpoints: [.finnhubProfiles, .finnhubTrades])
            group(
                "Lang & Schwarz",
                endpoints: [
                    .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope,
                ],
                detail: "Foreground EUR quote observations; scanner integration pending"
            )
            group(
                "Tradegate",
                endpoints: [.tradegate],
                detail: "Public quote collector · quote adapter pending"
            )
            group(
                "Euronext",
                endpoints: [.euronext],
                detail: "Public quote collector · quote adapter pending"
            )
            group("Yahoo Finance", endpoints: [.yahooPrimary, .yahooAlternate])
            group("Discovery", endpoints: [.wallstreetOnline, .traderFox])
            ScalableSettingsCard()
        }
        .onAppear {
            for endpoint in ProviderEndpoint.allCases {
                drafts[endpoint] =
                    ProviderEndpointStore.url(for: endpoint).absoluteString
            }
        }
    }

    private func group(
        _ title: String,
        endpoints: [ProviderEndpoint],
        detail: String? = nil
    ) -> some View {
        SettingsGroup(title: title) {
            if let detail {
                Text(detail).font(.body.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
            }
            ForEach(endpoints) { endpoint in
                ProviderEndpointRow(
                    endpoint: endpoint,
                    value: Binding(
                        get: { drafts[endpoint] ?? endpoint.defaultURL },
                        set: {
                            drafts[endpoint] = $0
                            checks[endpoint] = nil
                        }
                    ),
                    status: checks[endpoint] ?? "Not checked",
                    check: { check(endpoint) }
                )
            }
        }
    }

    private func check(_ endpoint: ProviderEndpoint) {
        guard endpoint != .finnhubTrades else { return }
        let value = drafts[endpoint] ?? endpoint.defaultURL
        checks[endpoint] = "Checking…"
        Task {
            do {
                try await ProviderEndpointChecker().check(value, for: endpoint)
                guard drafts[endpoint] == value else { return }
                checks[endpoint] =
                    endpoint.isUsedByNativeAdapter
                    ? "Market data reachable"
                    : "Address reachable · quote adapter pending"
            } catch {
                guard drafts[endpoint] == value else { return }
                checks[endpoint] = error.localizedDescription
            }
        }
    }

    private func save() {
        do {
            for endpoint in ProviderEndpoint.allCases {
                _ = try ProviderEndpointStore.validate(
                    drafts[endpoint] ?? endpoint.defaultURL,
                    for: endpoint
                )
            }
            for endpoint in ProviderEndpoint.allCases {
                try ProviderEndpointStore.save(
                    drafts[endpoint] ?? endpoint.defaultURL,
                    for: endpoint
                )
            }
            savingMessage =
                "Addresses saved. Active adapters use them on their next request."
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
        VStack(alignment: .leading, spacing: 5) {
            Text(endpoint.title).font(.body.weight(.light))
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
            Text(
                endpoint == .finnhubTrades
                    ? "Tested by the live Finnhub feed" : status
            )
            .font(.subheadline.weight(.light))
            .foregroundStyle(TrendsColors.supportingInk)
        }
    }
}

private struct ScalableSettingsCard: View {
    #if os(macOS)
        @State private var status = "Checking local session…"
    #endif

    var body: some View {
        SettingsGroup(title: "Scalable") {
            #if os(macOS)
                Text(status).font(.body.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
                TrendsActionButton(
                    title: "Login with Scalable",
                    systemImage: "person.crop.circle"
                ) {
                    Task {
                        do {
                            try await ScalableCLIService().startReadOnlyLogin()
                            status =
                                "Complete the Scalable sign-in in your browser."
                        } catch {
                            status = error.localizedDescription
                        }
                    }
                }
                .task {
                    status =
                        (try? await ScalableCLIService().isAuthorized()) == true
                        ? "Existing local CLI session is authorized."
                        : "Login is required on this Mac."
                }
            #else
                Text("iPad sign-in and quote access are not connected yet.")
                    .font(.body.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
            #endif
        }
    }
}
