import SwiftUI

/// Shows the combined discovery candidates.
struct RadarScannerDiagnostics: View {
    @Environment(RadarTableColorStore.self) private var colors
    @Environment(\.colorScheme) private var colorScheme
    let candidates: [RadarCompanyCandidate]
    let progress: MarketScanProgress?
    let listHeight: CGFloat
    @State private var search = ""
    @FocusState private var searchFocused: Bool

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
            VStack(alignment: .leading, spacing: 5) {
                Text("Search candidates")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                    TextField("Company name or ticker", text: $search)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .foregroundStyle(.primary)
                        .accessibilityLabel("Search market candidates")
                    if !search.isEmpty {
                        Button {
                            search = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear candidate search")
                    }
                }
                .padding(.horizontal, 12)
                .frame(minHeight: searchFieldHeight)
                .background(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.05),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(Color.accentColor.opacity(searchFocused ? 1 : 0.7),
                                      lineWidth: searchFocused ? 2 : 1.5)
                }
            }
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
            Text("Candle signals use fresh Yahoo minute bars with reported volume. German Yahoo candles are delayed.")
                .font(.caption2).foregroundStyle(color(.sourceMutedText))
        }
        .foregroundStyle(color(.sourceBodyText))
        .background(color(.sourceTableFill), in: RoundedRectangle(cornerRadius: 10))
        .trendsPanel()
    }

    private func color(_ role: RadarTableColorRole) -> Color {
        colors.color(role, dark: colorScheme == .dark)
    }

    private var searchFieldHeight: CGFloat {
        #if os(macOS)
        32
        #else
        44
        #endif
    }
}
