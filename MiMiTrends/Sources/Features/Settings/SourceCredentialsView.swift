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
