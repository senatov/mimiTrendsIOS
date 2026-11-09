import SwiftUI

struct DiscoverySettingsSection: View {
    @AppStorage(RadarDiscoveryPreferences.wikifolioKey) private var wikifolio = true
    @AppStorage(RadarDiscoveryPreferences.performanceKey) private var performance = true
    @AppStorage(RadarDiscoveryPreferences.priorityKey) private var priority = DiscoveryPriorityMode.balanced.rawValue
    @State private var health: [RankingSourceHealth] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Ranking sources")
                .font(SettingsTypography.label)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 8) { sources }
                VStack(alignment: .leading, spacing: 8) { sources }
            }
            Divider()
            Picker("Scan priority", selection: $priority) {
                ForEach(DiscoveryPriorityMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
            }
            .font(SettingsTypography.label)
            .pickerStyle(.menu)
            Text("Both lists refresh at startup and every 30 minutes. Ranking affects scan order, not signal confidence.")
                .font(.caption).foregroundStyle(.primary.opacity(0.78))
            Text("Wikifolio shows platform activity; turnover ranks value traded on the exchange. L&S and Finnhub validate live moves independently.")
                .font(.caption).foregroundStyle(.primary.opacity(0.78))
        }
        .task(id: "\(wikifolio)|\(performance)|\(priority)") {
            health = await WallstreetDiscoverySource.shared.health()
        }
    }

    @ViewBuilder
    private var sources: some View {
        source(.wikifolio, enabled: Binding(get: { wikifolio }, set: {
            wikifolio = $0
            if !$0 && !performance { performance = true }
        }), detail: "Today's most traded stocks on wikifolio")
        source(.performance, enabled: Binding(get: { performance }, set: {
            performance = $0
            if !$0 && !wikifolio { wikifolio = true }
        }), detail: "Top exchange turnover · daily list")
    }

    private func source(_ kind: WallstreetRankingKind, enabled: Binding<Bool>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(kind.title, isOn: enabled)
                .toggleStyle(.switch)
                .font(SettingsTypography.label)
                .accessibilityIdentifier("discovery-\(kind.rawValue)")
            Text(detail).font(.callout).foregroundStyle(.primary.opacity(0.72))
            Link(destination: ProviderEndpointStore.url(for: kind.endpoint)) {
                Text(ProviderEndpointStore.url(for: kind.endpoint).absoluteString)
                    .font(SettingsTypography.url).foregroundStyle(SettingsColors.url)
                    .lineLimit(2).truncationMode(.middle)
            }
            if let status = health.first(where: { $0.kind == kind }) {
                Text(!enabled.wrappedValue ? "Disabled" : status.failed ? "Refresh failed · retaining cached candidates" : status.lastSuccess == nil ? "Waiting for the first ranking refresh" : "\(status.count) ranked stocks · today's list")
                    .font(.caption).foregroundStyle(status.failed ? .orange : .primary.opacity(0.72))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
