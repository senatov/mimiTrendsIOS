import SwiftUI

struct ScannerSettingsView: View {
    @AppStorage("radar.historyLimit.v1") private var maxResults = 30
    @AppStorage("radar.historyAgeHours.v1") private var maxAgeHours = 2

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
            SettingsValueRow(title: "Candle signals", value: "Fresh Yahoo minute bars with reported volume")
            SettingsValueRow(title: "Historical data", value: "Saved Yahoo minute bars and daily summaries")
            SettingsValueRow(title: "Symbols", value: "Up to 200 US and German shares")
            SettingsValueRow(title: "Activity", value: "Foreground only")
            Text("Radar checks completed candles for rapid drops, rebounds and sustained rises. German data is delayed and the German scan stops when Xetra is closed. L&S quotes are available separately on the chart.")
                .font(.body.weight(.light))
                .foregroundStyle(TrendsColors.supportingInk)
        }
    }
}
