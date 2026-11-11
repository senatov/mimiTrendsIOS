import SwiftUI

struct RadarHeader: View {
    @Binding var symbol: String
    let candidateCount: Int?
    let sourcesOpen: Bool
    let onToggleSources: () -> Void
    let onRefresh: () -> Void
    let onManageWatchlist: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { symbolField; scanStatus; Spacer(minLength: 4); actionButtons }
            VStack(alignment: .leading, spacing: 6) {
                HStack { symbolField; Spacer(minLength: 4); scanStatus }
                HStack { Spacer(minLength: 0); actionButtons }
            }
        }
        .trendsPanel()
    }

    private var symbolField: some View {
        TextField("Ticker symbol", text: $symbol)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(maxWidth: 240)
            .accessibilityLabel("Radar symbol")
    }

    private var scanStatus: some View {
        Text(candidateCount.map { "\($0) market candidates" } ?? "Loading market candidates…")
            .font(.callout).foregroundStyle(.secondary)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            TrendsActionButton(title: "Sources", systemImage: "sidebar.right", action: onToggleSources)
                .accessibilityLabel(sourcesOpen ? "Hide sources" : "Show sources")
                .accessibilityValue(sourcesOpen ? "Open" : "Closed")
            TrendsActionButton(title: "Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                .accessibilityLabel("Refresh saved signals")
            watchlistButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var watchlistButton: some View {
        TrendsActionButton(title: "Edit watchlist", systemImage: "star", action: onManageWatchlist)
            .accessibilityIdentifier("editWatchlistButton")
    }
}
