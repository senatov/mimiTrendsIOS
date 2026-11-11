import SwiftUI

struct RadarHeader: View {
    @Binding var symbol: String
    let candidateCount: Int?
    let onManageWatchlist: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { symbolField; scanStatus; Spacer(minLength: 4); watchlistButton }
            VStack(alignment: .leading, spacing: 6) {
                HStack { symbolField; Spacer(minLength: 4); watchlistButton }
                scanStatus
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

    private var watchlistButton: some View {
        TrendsActionButton(title: "Edit watchlist", systemImage: "star", action: onManageWatchlist)
            .accessibilityIdentifier("editWatchlistButton")
    }
}
