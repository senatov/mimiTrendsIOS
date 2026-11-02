import SwiftUI

struct DiscoveryCandidateList: View {
    @Environment(\.scenePhase) private var scenePhase
    let snapshot: DiscoverySnapshot
    @State private var searchText = ""
    @State private var directQuotes: [String: WallstreetOnlineQuote] = [:]
    @State private var quoteMessage: String?

    var body: some View {
        List {
            Section {
                Text("Prices shown below come from the linked wallstreetONLINE pages and are in EUR. Rankings do not supply verified trading symbols or scanner signals.")
                    .font(.callout)
                    .foregroundStyle(TrendsColors.supportingInk)
                Text("Direct quote checks are limited to the first eight visible candidates. USD prices require a fresh EUR/USD quote; other currencies are omitted.")
                    .font(.caption)
                    .foregroundStyle(TrendsColors.supportingInk)
                if let quoteMessage { Text(quoteMessage).font(.caption).foregroundStyle(.secondary) }
                Text("Last fetch: \(Date(timeIntervalSince1970: TimeInterval(snapshot.refreshedAtMillis) / 1_000), style: .relative)")
                    .font(.caption)
                    .foregroundStyle(TrendsColors.supportingInk)
            }
            Section("\(filteredCandidates.count) candidates") {
                ForEach(filteredCandidates, id: \.identity) { candidate in
                    candidateRow(candidate)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Company or instrument path")
        .navigationTitle("Ranking candidates")
        .task(id: "\(searchText)|\(scenePhase)") { await loadDirectQuotes() }
    }

    private var filteredCandidates: [DiscoveryCandidate] {
        guard !searchText.isEmpty else { return snapshot.candidates }
        return snapshot.candidates.filter {
            ($0.displayName?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                $0.instrumentID.localizedCaseInsensitiveContains(searchText)
        }
    }

    private func candidateRow(_ candidate: DiscoveryCandidate) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(candidate.displayName ?? candidate.instrumentID)
                    .font(.body.weight(.regular))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let quote = directQuotes[candidate.instrumentID] {
                    Text(quote.priceEUR.formatted(.currency(code: "EUR")))
                        .monospacedDigit()
                }
                if let metrics = candidate.marketMetrics {
                    let change = metrics.changePercent(for: candidate.origin?.period)
                    Text(String(format: "%+.2f%%", change))
                        .monospacedDigit()
                        .foregroundStyle(change < 0 ? .red : .green)
                }
            }
            HStack(spacing: 8) {
                Text("#\(candidate.rank) · \(periodLabel(candidate.origin?.period))")
                Text(candidate.instrumentID)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(TrendsColors.supportingInk)
        }
        .accessibilityElement(children: .combine)
    }

    private func loadDirectQuotes() async {
        guard scenePhase == .active else {
            directQuotes = [:]
            return
        }
        do {
            try await Task.sleep(for: .milliseconds(300))
            let loaded = try await WallstreetOnlineQuoteSource().loadQuotes(
                for: Array(filteredCandidates.prefix(8))
            )
            guard !Task.isCancelled else { return }
            let store = try MarketQuoteStore(url: MarketQuoteStore.defaultURL())
            _ = try await store.record(loaded.values.map(MarketQuoteRecord.init),
                                       nowMillis: Int64(Date().timeIntervalSince1970 * 1_000))
            directQuotes = loaded
            quoteMessage = "\(loaded.count) recent linked page quotes in EUR."
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            directQuotes = [:]
            quoteMessage = error.localizedDescription
        }
    }

    private func periodLabel(_ period: DiscoveryRankingPeriod?) -> String {
        switch period {
        case .day: "1 day"
        case .week: "7 days"
        case .month: "30 days"
        case .year: "1 year"
        case .activity: "Activity"
        case nil: "Saved ranking"
        }
    }
}
