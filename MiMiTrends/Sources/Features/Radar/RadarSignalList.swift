import SwiftUI

struct RadarSignalList: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let signals: [ScanResult]
    let quoteMoves: [LSQuoteMove]
    let companyNames: [String: String]
    let selected: ScanResult?
    let compact: Bool
    let errorMessage: String?
    let onSelect: (ScanResult) -> Void
    let onRefresh: () -> Void
    @State private var sortColumn: RadarSortColumn = .movement
    @State private var ascending = false

    private var sortedSignals: [ScanResult] {
        signals.sorted { left, right in
            let comparison: ComparisonResult
            switch sortColumn {
            case .company:
                comparison = (companyNames[left.symbol] ?? left.symbol)
                    .localizedStandardCompare(companyNames[right.symbol] ?? right.symbol)
            case .event:
                comparison = left.signalSource.localizedStandardCompare(right.signalSource)
            case .movement:
                comparison = left.windowChangePercent == right.windowChangePercent ? .orderedSame
                    : left.windowChangePercent < right.windowChangePercent ? .orderedAscending : .orderedDescending
            case .price:
                comparison = left.price == right.price ? .orderedSame
                    : left.price < right.price ? .orderedAscending : .orderedDescending
            case .age:
                // A smaller age means a newer signal, so compare timestamps in reverse.
                comparison = left.signalEpochMillis == right.signalEpochMillis ? .orderedSame
                    : left.signalEpochMillis > right.signalEpochMillis ? .orderedAscending : .orderedDescending
            }
            if comparison == .orderedSame { return left.symbol < right.symbol }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Live radar").font(.title3.weight(.light))
                Text("\(signals.count) signals")
                    .font(.subheadline)
                    .foregroundStyle(tableColor(.mutedText))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
                    .accessibilityLabel("Refresh saved signals")
            }
            Divider()
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if !quoteMoves.isEmpty {
                Text("Preliminary Lang & Schwarz quote moves · trade volume unverified")
                    .font(.caption)
                    .foregroundStyle(tableColor(.mutedText))
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(quoteMoves) { move in
                            HStack(spacing: 8) {
                                Text(move.quote.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%+.2f%%", move.changePercent))
                                    .foregroundStyle(move.changePercent < 0 ? tableColor(.fall) : tableColor(.rise))
                                Text(move.quote.midpointEUR.formatted(.currency(code: "EUR")))
                                    .monospacedDigit()
                            }
                            .font(.subheadline)
                        }
                    }
                }
                .frame(maxHeight: 150)
                Divider()
            }
            if signals.isEmpty && quoteMoves.isEmpty {
                VStack {
                    Spacer(minLength: 16)
                    Text("Waiting for a confirmed rise or drop in minute candles")
                        .font(.title2.weight(.light))
                        .foregroundStyle(TrendsColors.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !signals.isEmpty {
                if !compact {
                    HStack(spacing: 0) {
                        sortButton(.company).frame(maxWidth: .infinity, alignment: .leading)
                        sortButton(.event).frame(width: 285, alignment: .leading)
                        sortButton(.movement).frame(width: 115, alignment: .trailing)
                        sortButton(.price).frame(width: 70, alignment: .trailing)
                        sortButton(.age).frame(width: 50, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .foregroundStyle(tableColor(.headerText))
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(tableColor(.headerFill))
                    .overlay(RadarSignalColumnLines(color: tableColor(.grid), horizontalInset: 8))
                    .overlay(alignment: .bottom) { tableSeparator }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(sortedSignals.map(RadarSignalItem.init)) { item in
                            RadarSignalRow(
                                signal: item.signal,
                                companyName: companyNames[item.signal.symbol] ?? item.signal.symbol,
                                compact: compact,
                                isSelected: isSelected(item.signal),
                                onSelect: { onSelect(item.signal) }
                            )
                            .accessibilityAddTraits(isSelected(item.signal) ? [.isSelected] : [])
                            tableSeparator
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(tableColor(.bodyText))
        .trendsPanel()
    }

    private func sortButton(_ column: RadarSortColumn) -> some View {
        Button {
            if sortColumn == column { ascending.toggle() }
            else {
                sortColumn = column
                ascending = column == .company || column == .event
            }
        } label: {
            HStack(spacing: 3) {
                Text(column.title)
                if sortColumn == column {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                }
            }
            .frame(maxWidth: .infinity, alignment: column == .company || column == .event ? .leading : .trailing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Sort by \(column.title)")
        .accessibilityValue(sortColumn == column ? (ascending ? "Ascending" : "Descending") : "Unsorted")
    }

    private var tableSeparator: some View {
        Rectangle()
            .fill(tableColor(.grid))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }

    private func isSelected(_ signal: ScanResult) -> Bool {
        signal.symbol == selected?.symbol &&
            signal.signalSource == selected?.signalSource &&
            signal.signalEpochMillis == selected?.signalEpochMillis
    }
}

private enum RadarSortColumn {
    case company, event, movement, price, age

    var title: String {
        switch self {
        case .company: "Company"
        case .event: "Event"
        case .movement: "Movement"
        case .price: "Price"
        case .age: "Age"
        }
    }
}

private struct RadarSignalItem: Identifiable {
    let signal: ScanResult
    var id: String { "\(signal.symbol)|\(signal.signalSource)|\(signal.signalEpochMillis)" }
}
