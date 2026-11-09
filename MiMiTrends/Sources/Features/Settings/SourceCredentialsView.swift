import SwiftUI

struct SourceCredentialsView: View {
    var body: some View {
        SettingsPage(
            title: "Market data providers",
            subtitle: "Configure the active Radar sources and the live trade feed"
        ) { width in
            VStack(alignment: .leading, spacing: 18) {
                TradeImportSettingsSection(width: width)
                DiscoverySettingsSection()
                ProviderSettingsPanel(width: width)
                SettingsGroup(title: "FMP · optional") {
                    CredentialEditor(
                        title: "Financial Modeling Prep API key",
                        detail: "Optional market candidates, company profiles and fallback daily history. Charts work without this key.",
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
                    Text("The key switches candidate discovery on the next Radar scan. L&S quote signals and Yahoo candle signals retain separate validation. FMP mover results do not include a source timestamp.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
