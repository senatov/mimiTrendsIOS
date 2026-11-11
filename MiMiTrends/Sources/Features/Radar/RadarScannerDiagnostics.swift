import SwiftUI

/// Shows the combined discovery candidates.
struct RadarScannerDiagnostics: View {
    @Environment(RadarTableColorStore.self) private var colors
    @Environment(\.colorScheme) private var colorScheme
    let candidates: [RadarCompanyCandidate]
    let progress: MarketScanProgress?
    let listHeight: CGFloat
    @State private var search = ""

    private var visible: [RadarCompanyCandidate] {
        candidates.filter {
            search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) ||
                $0.symbol.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Market candidates").font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text("\(candidates.count) shares").monospacedDigit()
                    .font(.caption).foregroundStyle(color(.sourceMutedText))
            }
            if let progress, progress.total > 0 {
                Text("Candles \(progress.processed)/\(progress.total) · usable \(progress.successful) · skipped \(progress.skipped) · errors \(progress.errors)")
                    .font(.caption.monospacedDigit()).foregroundStyle(color(.sourceMutedText))
            }
            TextField("Find company or ticker", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Filter scanner candidates")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(visible, id: \.symbol) { candidate in
                        HStack {
                            Text(RadarSearchKeyword.cleanedCompanyName(candidate.name, symbol: candidate.symbol))
                                .font(.callout).lineLimit(1)
                            Spacer(minLength: 4)
                            Text(candidate.symbol).font(.caption.monospaced())
                                .foregroundStyle(color(.sourceMutedText))
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        Divider()
                    }
                    if visible.isEmpty {
                        Text(candidates.isEmpty ? "Preparing the scan pool…" : "No matching candidates")
                            .font(.callout).padding(.vertical, 12)
                    }
                }
            }
            .frame(height: listHeight)
            Text("Candle signals: Finnhub live trades or US Yahoo candles verified against a fresh Finnhub price.")
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
