import SwiftUI

struct SourceCredentialsView: View {
    var body: some View {
        SettingsPage(
            title: "Market data providers",
            subtitle: "Configure the active Radar sources and the live trade feed"
        ) { width in
            VStack(alignment: .leading, spacing: 18) {
                TradeImportSettingsSection(width: width)
                ProviderSettingsPanel(width: width)
            }
        }
    }
}
