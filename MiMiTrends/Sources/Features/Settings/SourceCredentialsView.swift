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
                ProviderSettingsPanel(width: width)
                SettingsGroup(title: "Finnhub access") {
                    finnhubKeyEditor
                    Text("Required for the live trade feed and optional US bid/ask validation.")
                        .font(.body.weight(.light))
                        .foregroundStyle(TrendsColors.supportingInk)
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
