import SwiftUI

struct ScannerSettingsView: View {
    @AppStorage("radar.historyLimit.v1") private var maxResults = 30
    @AppStorage("radar.historyAgeHours.v1") private var maxAgeHours = 2
    @AppStorage("radar.scanWatchlist.v1") private var scanWatchlist = false

    var body: some View {
        SettingsPage(title: "Scanner", subtitle: "Current radar scope and saved results") { width in
            if width >= 900 {
                HStack(alignment: .top, spacing: 18) {
                    resultPanel
                    scopePanel
                }
            } else {
                resultPanel
                scopePanel
            }
        }
    }

    private var resultPanel: some View {
        SettingsGroup(title: "Saved signal display") {
            Stepper(value: $maxResults, in: 5...100, step: 5) {
                SettingsValueRow(title: "Maximum results", value: maxResults.formatted())
            }
            .accessibilityLabel("Maximum results")
            Stepper(value: $maxAgeHours, in: 1...72) {
                SettingsValueRow(title: "Maximum signal age", value: "\(maxAgeHours) h")
            }
            .accessibilityLabel("Maximum signal age")
            Text("These limits filter the saved Radar list on this device. They do not delete signals from the database.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
        }
    }

    private var scopePanel: some View {
        SettingsGroup(title: "Current scan scope") {
            SettingsValueRow(title: "Confirmed signals", value: "Yahoo minute bars; optional Finnhub trades")
            SettingsValueRow(title: "Preliminary quotes", value: "Lang & Schwarz; linked wallstreetONLINE prices on demand")
            SettingsValueRow(title: "Symbols", value: scanWatchlist ? "Selected + saved, up to 5" : "Selected only")
            SettingsValueRow(title: "Activity", value: "Foreground only")
            Text("Quote movements have no verified trade volume. Existing source-currency minute bars remain separate from EUR quote observations.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
        }
    }
}
