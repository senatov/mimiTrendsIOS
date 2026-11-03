import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RadarSignalList: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    let signals: [ScanResult]
    let showingSavedHistory: Bool
    let quoteMoves: [LSQuoteMove]
    let companyNames: [String: String]
    let companyMetadata: [String: RadarCompanyMetadata]
    let selected: ScanResult?
    let compact: Bool
    let errorMessage: String?
    let onSelect: (ScanResult) -> Void
    let onRefresh: () -> Void
    @State private var sortColumn: RadarSortColumn = .movement
    @State private var ascending = false
    @State private var availableWidth: CGFloat = 0
    @State private var columnWidthOverrides: [RadarSortColumn: CGFloat] = [:]
    @State private var coverageRequest: RadarCoverageRequest?
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
                Text(showingSavedHistory ? "Saved radar" : "Live radar")
                    .font(.title3.weight(.light))
                Text("\(signals.count) signals")
                    .font(.subheadline)
                    .foregroundStyle(tableColor(.signalMutedText))
                Spacer()
                Button("Refresh", systemImage: "arrow.clockwise", action: onRefresh)
                    .labelStyle(.iconOnly)
                    .buttonStyle(TrendsActionButtonStyle(compact: true))
                    .accessibilityLabel("Refresh saved signals")
            }
            Divider()
            if showingSavedHistory {
                Text("Older saved signals · no new confirmed signals yet")
                    .font(.caption).foregroundStyle(tableColor(.signalMutedText))
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
            if !quoteMoves.isEmpty {
                Text("Preliminary Lang & Schwarz quote moves · trade volume unverified")
                    .font(.caption)
                    .foregroundStyle(tableColor(.signalMutedText))
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
                .frame(height: min(150, CGFloat(quoteMoves.count) * 27))
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
                                    companyMetadata: companyMetadata[item.signal.symbol],
                                    compact: compact,
                                    isSelected: isSelected(item.signal),
                                    widths: widths,
                                    onSelect: { onSelect(item.signal) },
                                    onShowCoverage: { coverageRequest = $0 }
                                )
                                .accessibilityAddTraits(isSelected(item.signal) ? [.isSelected] : [])
                                tableSeparator
                            }
                        }
                    }
                    .frame(width: contentWidth + (compact ? 0 : scrollbarGutter), alignment: .leading)
                    .onAppear { availableWidth = contentWidth }
                    .onChange(of: contentWidth) { oldValue, newValue in
                        guard abs(newValue - oldValue) > 1 else { return }
                        availableWidth = newValue
                        columnWidthOverrides = [:]
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(tableColor(.signalBodyText))
        .background(tableColor(.signalTableFill), in: RoundedRectangle(cornerRadius: 10))
        .trendsPanel()
        .sheet(item: $coverageRequest) { request in
            RadarCoverageView(request: request)
                .frame(minWidth: 360, minHeight: 260)
        }
    }

    private var header: some View {
        let widths = fittedWidths(availableWidth: max(0, availableWidth - 16))
        return HStack(spacing: 0) {
            ForEach(RadarSortColumn.allCases, id: \.self) { column in
                headerCell(column, width: widths.width(for: column))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(tableTypography.font(size: tableTypography.size))
        .foregroundStyle(tableColor(.signalHeaderText))
        .padding(.leading, 8)
        .padding(.trailing, 8 + scrollbarGutter)
        .padding(.vertical, 5)
        .background(tableColor(.signalHeaderFill))
        .overlay {
            RadarSignalColumnLines(widths: widths, color: tableColor(.signalGrid), horizontalInset: 8)
                .padding(.trailing, scrollbarGutter)
        }
        .overlay(alignment: .bottom) { tableSeparator }
    }

    private func headerCell(_ column: RadarSortColumn, width: CGFloat) -> some View {
        HStack(spacing: 4) {
            Text(column.title)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: column.isNumeric ? .trailing : .leading)
            Button { toggleSort(column) } label: {
                Image(systemName: sortColumn == column ? (ascending ? "chevron.up" : "chevron.down") : "arrow.up.arrow.down")
                    .font(.system(size: sortColumn == column ? 9 : 8, weight: .semibold))
                    .foregroundStyle(sortColumn == column ? Color.white : tableColor(.signalHeaderText))
                    .frame(width: 18, height: 18)
                    .background(sortColumn == column ? tableColor(.signalActionAccent) : tableColor(.signalHeaderFill).opacity(0.72), in: Circle())
                    .overlay { Circle().strokeBorder(tableColor(.signalHeaderText).opacity(sortColumn == column ? 0.28 : 0.32), lineWidth: 0.7) }
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
                .onTapGesture(count: 2) { autoFit(column) }
                .help("Drag to resize · double-click to fit content")
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
        updated[column] = min(max(width, column.minimumWidth), column.maximumWidth)
        columnWidthOverrides = updated
    }

    private func autoFit(_ column: RadarSortColumn) {
        let names = signals.map { companyNames[$0.symbol] ?? $0.symbol }
        let contentWidths = RadarSignalColumnWidths.contentWidths(
            signals: signals, companyNames: names, fontSize: tableTypography.size
        )
        setWidth(contentWidths[column] ?? column.minimumWidth, for: column)
    }

    private func fittedWidths(availableWidth: CGFloat) -> RadarSignalColumnWidths {
        RadarSignalColumnWidths.fit(
            signals: signals,
            companyNames: signals.map { companyNames[$0.symbol] ?? $0.symbol },
            availableWidth: availableWidth,
            overrides: columnWidthOverrides,
            fontSize: tableTypography.size
        )
    }

    private var tableSeparator: some View {
        Rectangle()
            .fill(tableColor(.signalGrid))
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
        case .movement: 116
        case .price: 88
        case .age: 84
        }
    }

    var maximumWidth: CGFloat {
        switch self {
        case .company: 300
        case .event: 280
        case .movement: 190
        case .price: 140
        case .age: 110
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
        companyNames: [String],
        availableWidth: CGFloat,
        overrides: [RadarSortColumn: CGFloat],
        fontSize: Double
    ) -> Self {
        let contentWidths = Self.contentWidths(
            signals: signals, companyNames: companyNames, fontSize: fontSize
        )
        var widths = Dictionary(uniqueKeysWithValues: RadarSortColumn.allCases.map { column in
            let fitted = min(max(contentWidths[column] ?? column.minimumWidth, column.minimumWidth), column.maximumWidth)
            let requested = overrides[column] ?? fitted
            return (column, min(max(requested, column.minimumWidth), column.maximumWidth))
        })

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

    static func contentWidths(
        signals: [ScanResult], companyNames: [String], fontSize: Double
    ) -> [RadarSortColumn: CGFloat] {
        [
            .company: measuredWidth(companyNames, fontSize: fontSize) + 50,
            .event: max(205, measuredWidth(signals.map(eventLabel), fontSize: fontSize) + 108),
            .movement: measuredWidth(signals.map {
                String(format: "%+.2f%% / %@", $0.windowChangePercent, $0.signalWindowLabel)
            }, fontSize: fontSize) + 24,
            .price: measuredWidth(signals.map {
                $0.price.formatted(.number.precision(.fractionLength(0...2)))
            }, fontSize: fontSize) + 30,
            .age: 70
        ]
    }

    private static func measuredWidth(_ values: [String], fontSize: Double) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont.systemFont(ofSize: fontSize)
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
