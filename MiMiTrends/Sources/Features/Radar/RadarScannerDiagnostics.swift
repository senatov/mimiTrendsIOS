import SwiftUI

/// Shows the actual admitted candle pool, rather than one ranking's input list.
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
                Text("Candle scan").font(.subheadline.weight(.medium))
                Spacer(minLength: 4)
                Text("\(candidates.count) shares").monospacedDigit()
                    .font(.caption).foregroundStyle(color(.sourceMutedText))
            }
            if let progress {
                Text("\(progress.processed) / \(progress.total) checked · \(progress.successful) with current candles")
                    .font(.caption).foregroundStyle(color(.sourceMutedText))
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
            Text("Completed candles + volume · German session and delay checks apply")
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
