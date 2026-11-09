import SwiftUI

struct SourceCredentialsView: View {
    @Environment(RadarSession.self) private var radarSession

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
                SettingsGroup(title: "Finnhub access") {
                    finnhubKeyEditor
                    finnhubWebhookSecretEditor
                    Text("Required for the live trade feed and optional US bid/ask validation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("The webhook secret is stored separately. The current app does not receive Finnhub webhooks; this value does not affect the live trade feed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var finnhubKeyEditor: some View {
        CredentialEditor(
            title: "Finnhub API key",
            detail: "Stored securely on this device.",
            load: { try FinnhubCredentialStore.load() },
            save: { try FinnhubCredentialStore.save($0) },
            remove: {
                try FinnhubCredentialStore.delete()
                radarSession.stop()
            }
        )
    }

    private var finnhubWebhookSecretEditor: some View {
        CredentialEditor(
            title: "Finnhub webhook secret",
            detail: "Stored separately on this device.",
            load: { try FinnhubCredentialStore.loadWebhookSecret() },
            save: { try FinnhubCredentialStore.saveWebhookSecret($0) },
            remove: { try FinnhubCredentialStore.deleteWebhookSecret() }
        )
    }
}
