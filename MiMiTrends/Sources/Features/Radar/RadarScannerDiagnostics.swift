import SwiftUI

/// A compact, read-only view of the scanner's input, kept beside the Radar signals.
struct RadarScannerDiagnostics: View {
    @Environment(RadarTableColorStore.self) private var colors
    @Environment(\.colorScheme) private var colorScheme
    let snapshot: DiscoverySnapshot
    let progress: MarketScanProgress?
    let listHeight: CGFloat
    @State private var search = ""
    @AppStorage(RadarDiscoveryPreferences.priorityKey) private var priorityMode = DiscoveryPriorityMode.balanced.rawValue
    @AppStorage(RadarDiscoveryPreferences.wikifolioKey) private var wikifolio = true
    @AppStorage(RadarDiscoveryPreferences.performanceKey) private var performance = true

    private var settings: RadarDiscoveryPreferences {
        var result = RadarDiscoveryPreferences()
        result.priority = DiscoveryPriorityMode(rawValue: priorityMode) ?? .balanced
        result.wikifolio = wikifolio
        result.performance = performance
        return result
    }

    private func priority(_ candidate: DiscoveryCandidate) -> Double {
        candidate.rankingEvidence?.priority(settings: settings) ?? candidate.discoveryPriority ?? 0
    }

    private var candidates: [DiscoveryCandidate] {
        snapshot.candidates.filter {
            search.isEmpty || ($0.displayName ?? $0.instrumentID).localizedCaseInsensitiveContains(search)
        }.sorted {
            let left = priority($0), right = priority($1)
            return left == right ? $0.instrumentID < $1.instrumentID : left > right
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Scanner candidates").font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text("\(snapshot.candidates.count) ranked").monospacedDigit()
                    .font(.caption).foregroundStyle(color(.sourceMutedText))
            }
            if let progress {
                Text("Market scan · \(progress.processed) / \(progress.total) checked")
                    .font(.caption).foregroundStyle(color(.sourceMutedText))
            }
            TextField("Find company", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter scanner candidates")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(candidates, id: \.identity) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(candidate.displayName ?? candidate.instrumentID)
                                    .font(.callout).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(priority(candidate), format: .number.precision(.fractionLength(1)))
                                    .font(.caption.monospacedDigit())
                                    .help("Scan priority, not signal confidence")
                            }
                            if let evidence = candidate.rankingEvidence {
                                HStack(spacing: 8) {
                                    if let rank = evidence.wikifolioRank { Text("Wikifolio #\(rank)") }
                                    if let rank = evidence.performanceRank { Text("Turnover #\(rank)") }
                                }
                                .font(.caption2).foregroundStyle(color(.sourceMutedText))
                            }
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                    if candidates.isEmpty {
                        Text("No matching candidates").font(.callout).padding(.vertical, 12)
                    }
                }
            }
            .frame(height: listHeight)
            Text("Ranking priority · not a trading signal")
                .font(.caption2).foregroundStyle(color(.sourceMutedText))
        }
        .foregroundStyle(color(.sourceBodyText))
        .background(color(.sourceTableFill), in: RoundedRectangle(cornerRadius: 10))
        .trendsPanel()
    }

    private func color(_ role: RadarTableColorRole) -> Color {
        colors.color(role, dark: colorScheme == .dark)
    }
}
