import SwiftUI

struct DiscoverySettingsSection: View {
    @AppStorage(RadarDiscoveryPreferences.wikifolioKey) private var wikifolio = true
    @AppStorage(RadarDiscoveryPreferences.performanceKey) private var performance = true
    @AppStorage(RadarDiscoveryPreferences.priorityKey) private var priority = DiscoveryPriorityMode.balanced.rawValue
    @State private var health: [RankingSourceHealth] = []

    var body: some View {
        SettingsGroup(title: "Radar discovery & priority") {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) { sources }
                VStack(alignment: .leading, spacing: 16) { sources }
            }
            Divider()
            Picker("Scan priority", selection: $priority) {
                ForEach(DiscoveryPriorityMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
            }
            .font(SettingsTypography.label)
            .pickerStyle(.menu)
            Text("Both lists refresh at startup and every 30 minutes. Ranking position and presence in both lists determine scan order; they do not increase signal confidence.")
                .font(.callout).foregroundStyle(.secondary)
            Text("Wikifolio trades measure activity on wikifolio, not exchange volume. Fresh L&S bid/ask movements and Yahoo candle signals keep their own validation.")
                .font(.callout).foregroundStyle(.secondary)
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
        }), detail: "Today's price-performance ranking")
    }

    private func source(_ kind: WallstreetRankingKind, enabled: Binding<Bool>, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(kind.title, isOn: enabled)
                .toggleStyle(.switch)
                .font(SettingsTypography.label)
                .accessibilityIdentifier("discovery-\(kind.rawValue)")
            Text(detail).font(.callout).foregroundStyle(.secondary)
            Link(destination: ProviderEndpointStore.url(for: kind.endpoint)) {
                Text(ProviderEndpointStore.url(for: kind.endpoint).absoluteString)
                    .font(SettingsTypography.url).foregroundStyle(SettingsColors.url)
                    .lineLimit(2).truncationMode(.middle)
            }
            if let status = health.first(where: { $0.kind == kind }) {
                Text(!enabled.wrappedValue ? "Disabled" : status.failed ? "Refresh failed · retaining cached candidates" : status.lastSuccess == nil ? "Waiting for the first ranking refresh" : "\(status.count) ranked stocks · today's list")
                    .font(.caption).foregroundStyle(status.failed ? .orange : .secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
