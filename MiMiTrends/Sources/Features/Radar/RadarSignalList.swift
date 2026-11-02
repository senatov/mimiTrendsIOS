import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    @State private var availableWidth: CGFloat = 0
    @State private var columnWidthOverrides: [RadarSortColumn: CGFloat] = [:]
    private var scrollbarGutter: CGFloat {
        #if os(macOS)
        CGFloat(NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
        #else
        0
        #endif
    }

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
                    header
                }
                GeometryReader { geometry in
                    let contentWidth = max(0, geometry.size.width - (compact ? 0 : scrollbarGutter))
                    let widths = fittedWidths(availableWidth: contentWidth - 16)
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedSignals.map(RadarSignalItem.init)) { item in
                                RadarSignalRow(
                                    signal: item.signal,
                                    companyName: companyNames[item.signal.symbol] ?? item.signal.symbol,
                                    compact: compact,
                                    isSelected: isSelected(item.signal),
                                    widths: widths,
                                    onSelect: { onSelect(item.signal) }
                                )
                                .accessibilityAddTraits(isSelected(item.signal) ? [.isSelected] : [])
                                tableSeparator
                            }
                        }
                    }
                    .frame(width: contentWidth + (compact ? 0 : scrollbarGutter), alignment: .leading)
                    .onAppear { availableWidth = contentWidth }
                    .onChange(of: contentWidth) { _, newValue in availableWidth = newValue }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(tableColor(.bodyText))
        .trendsPanel()
    }

    private var header: some View {
        let widths = fittedWidths(availableWidth: max(0, availableWidth - 16))
        return HStack(spacing: 0) {
            ForEach(RadarSortColumn.allCases, id: \.self) { column in
                headerCell(column, width: widths.width(for: column))
            }
        }
        .font(.system(size: 13, weight: .regular))
        .foregroundStyle(tableColor(.headerText))
        .padding(.leading, 8)
        .padding(.trailing, 8 + scrollbarGutter)
        .padding(.vertical, 5)
        .background(tableColor(.headerFill))
        .overlay {
            RadarSignalColumnLines(widths: widths, color: tableColor(.grid), horizontalInset: 8)
                .padding(.trailing, scrollbarGutter)
        }
        .overlay(alignment: .bottom) { tableSeparator }
    }

    private func headerCell(_ column: RadarSortColumn, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(column.title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: column.isNumeric ? .trailing : .leading)
            Button { toggleSort(column) } label: {
                Image(systemName: sortColumn == column ? (ascending ? "chevron.up" : "chevron.down") : "arrow.up.arrow.down")
                    .font(.system(size: sortColumn == column ? 9 : 8, weight: .semibold))
                    .foregroundStyle(sortColumn == column ? Color.white : tableColor(.headerText))
                    .frame(width: 18, height: 18)
                    .background(sortColumn == column ? tableColor(.actionAccent) : tableColor(.headerFill).opacity(0.72), in: Circle())
                    .overlay { Circle().strokeBorder(tableColor(.headerText).opacity(sortColumn == column ? 0.28 : 0.32), lineWidth: 0.7) }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 12)
            .accessibilityLabel("Sort by \(column.title)")
            .accessibilityValue(sortColumn == column ? (ascending ? "Ascending" : "Descending") : "Unsorted")
        }
        .padding(.horizontal, 6)
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.clear)
                .frame(width: 10)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onEnded { value in
                    setWidth(width + value.translation.width, for: column)
                })
                .onTapGesture(count: 2) { columnWidthOverrides[column] = nil }
                .help("Drag to resize · double-click to auto-fit")
        }
    }

    private func toggleSort(_ column: RadarSortColumn) {
        if sortColumn == column { ascending.toggle() }
        else {
            sortColumn = column
            ascending = column == .company || column == .event
        }
    }

    private func setWidth(_ width: CGFloat, for column: RadarSortColumn) {
        var updated = columnWidthOverrides
        updated[column] = min(max(width, column.minimumWidth), 520)
        columnWidthOverrides = updated
    }

    private func fittedWidths(availableWidth: CGFloat) -> RadarSignalColumnWidths {
        RadarSignalColumnWidths.fit(
            signals: signals,
            availableWidth: availableWidth,
            overrides: columnWidthOverrides
        )
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

enum RadarSortColumn: CaseIterable {
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

    var isNumeric: Bool { self == .movement || self == .price || self == .age }

    var minimumWidth: CGFloat {
        switch self {
        case .company: 100
        case .event: 180
        case .movement: 100
        case .price: 78
        case .age: 70
        }
    }
}

struct RadarSignalColumnWidths {
    let company: CGFloat
    let event: CGFloat
    let movement: CGFloat
    let price: CGFloat
    let age: CGFloat

    func width(for column: RadarSortColumn) -> CGFloat {
        switch column {
        case .company: company
        case .event: event
        case .movement: movement
        case .price: price
        case .age: age
        }
    }

    static func fit(
        signals: [ScanResult],
        availableWidth: CGFloat,
        overrides: [RadarSortColumn: CGFloat]
    ) -> Self {
        let preferred: [RadarSortColumn: CGFloat] = [
            .company: overrides[.company] ?? 100,
            .event: overrides[.event] ?? max(205, measuredWidth(signals.map(eventLabel)) + 100),
            .movement: overrides[.movement] ?? max(100, measuredWidth(signals.map { String(format: "%+.2f%% / %@", $0.windowChangePercent, $0.signalWindowLabel) }) + 34),
            .price: overrides[.price] ?? max(78, measuredWidth(signals.map { $0.price.formatted(.number.precision(.fractionLength(0...2))) }) + 30),
            .age: overrides[.age] ?? 70
        ]
        var widths = Dictionary(uniqueKeysWithValues: RadarSortColumn.allCases.map { column in
            (column, min(max(preferred[column] ?? column.minimumWidth, column.minimumWidth), 520))
        })
        let otherColumns: [RadarSortColumn] = [.event, .movement, .price, .age]
        let otherWidth = otherColumns.reduce(CGFloat.zero) { $0 + (widths[$1] ?? $1.minimumWidth) }
        if overrides[.company] == nil {
            widths[.company] = max(RadarSortColumn.company.minimumWidth, availableWidth - otherWidth)
        }

        let minimumTableWidth = RadarSortColumn.allCases.reduce(CGFloat.zero) { $0 + $1.minimumWidth }
        var overflow = max(0, widths.values.reduce(0, +) - max(availableWidth, minimumTableWidth))
        for column in RadarSortColumn.allCases {
            guard overflow > 0 else { break }
            let current = widths[column] ?? column.minimumWidth
            let reduction = min(overflow, current - column.minimumWidth)
            widths[column] = current - reduction
            overflow -= reduction
        }

        return Self(
            company: widths[.company] ?? RadarSortColumn.company.minimumWidth,
            event: widths[.event] ?? RadarSortColumn.event.minimumWidth,
            movement: widths[.movement] ?? RadarSortColumn.movement.minimumWidth,
            price: widths[.price] ?? RadarSortColumn.price.minimumWidth,
            age: widths[.age] ?? RadarSortColumn.age.minimumWidth
        )
    }

    private static func measuredWidth(_ values: [String]) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 13)
        #else
        let font = UIFont.systemFont(ofSize: 13)
        #endif
        return values.prefix(200).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }

    private static func eventLabel(_ signal: ScanResult) -> String {
        let label: String
        switch signal.signalSource.lowercased() {
        case "rapid crash": label = "‼ RAPID CRASH"
        case "rapid rise": label = "↑ RAPID RISE"
        case "sustained drop": label = "↓ SUSTAINED DROP"
        case "sustained rise": label = "↑ SUSTAINED RISE"
        case "tradable corridor": label = "▰ CORRIDOR"
        default: label = signal.signalSource.uppercased()
        }
        return signal.isRetained ? "\(label) · RECENT" : label
    }
}

private struct RadarSignalItem: Identifiable {
    let signal: ScanResult
    var id: String { "\(signal.symbol)|\(signal.signalSource)|\(signal.signalEpochMillis)" }
}
