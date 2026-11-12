import SwiftUI

struct RadarHeader: ToolbarContent {
    @Binding var symbol: String
    let candidateCount: Int?
    let sourcesOpen: Bool
    let onToggleSources: () -> Void
    let onRefresh: () -> Void
    let onManageWatchlist: () -> Void

    var body: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) { symbolField }
        ToolbarItemGroup(placement: .topBarTrailing) { actionButtons }
        #else
        ToolbarItem(placement: .navigation) { symbolField }
        ToolbarItemGroup(placement: .automatic) { actionButtons }
        #endif
    }

    private var symbolField: some View {
        TextField("Ticker symbol", text: $symbol)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .frame(width: 200)
            .accessibilityLabel("Radar symbol")
    }

    private var actionButtons: some View {
        Group {
            TrendsActionButton(title: "Sources", systemImage: "sidebar.right", showsTitle: false, action: onToggleSources)
                .accessibilityLabel(sourcesOpen ? "Hide sources" : "Show sources")
                .accessibilityValue(sourcesOpen ? "Open" : "Closed")
            TrendsActionButton(title: "Refresh", systemImage: "arrow.clockwise", showsTitle: false, action: onRefresh)
                .accessibilityLabel("Refresh saved signals")
                .accessibilityValue(candidateCount.map { "\($0) market candidates" } ?? "Loading market candidates")
            watchlistButton
        }
    }

    private var watchlistButton: some View {
        TrendsActionButton(title: "Edit watchlist", systemImage: "star", showsTitle: false, action: onManageWatchlist)
            .accessibilityIdentifier("editWatchlistButton")
    }
}
