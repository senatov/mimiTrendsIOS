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
                SettingsGroup(title: "FMP market candidates") {
                    CredentialEditor(
                        title: "Financial Modeling Prep API key",
                        detail: "Use FMP JSON movers instead of the TraderFox HTML candidate page.",
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
                    Text("Required for the live trade feed and optional US bid/ask validation.")
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
}
