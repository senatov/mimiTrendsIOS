import SwiftUI
#if os(macOS)
import AppKit
#endif

struct RadarSignalList: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    let signals: [ScanResult]
    let showingSavedHistory: Bool
    let activity: RadarActivity?
    let companyNames: [String: String]
    let companyMetadata: [String: RadarCompanyMetadata]
    let currencyRates: DisplayCurrencyRates?
    let displayCurrency: String
    let selected: ScanResult?
    let compact: Bool
    let errorMessage: String?
    let sourcesOpen: Bool
    let onToggleSources: () -> Void
    let onSelect: (ScanResult) -> Void
    let onVisibleSignal: (String) async -> Void
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
            case .window:
                let lhs = Int(left.signalWindowLabel.prefix { $0.isNumber }) ?? 0
                let rhs = Int(right.signalWindowLabel.prefix { $0.isNumber }) ?? 0
                comparison = lhs == rhs ? .orderedSame : lhs < rhs ? .orderedAscending : .orderedDescending
            case .price:
                let lhs = currencyRates?.convert(left.price, from: left.priceCurrency ?? "USD", to: displayCurrency)
                    ?? (left.priceCurrency == displayCurrency ? left.price : nil)
                let rhs = currencyRates?.convert(right.price, from: right.priceCurrency ?? "USD", to: displayCurrency)
                    ?? (right.priceCurrency == displayCurrency ? right.price : nil)
                comparison = lhs == rhs ? .orderedSame
                    : (lhs ?? -.infinity) < (rhs ?? -.infinity) ? .orderedAscending : .orderedDescending
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
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(showingSavedHistory ? "Saved radar" : "Live radar")
                    .font(.subheadline.weight(.semibold))
                Text("\(signals.count) signals")
                    .font(.subheadline)
                    .foregroundStyle(tableColor(.signalMutedText))
                Text(displayCurrency)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tableColor(.signalHeaderFill), in: Capsule())
                    .help(currencyRates.map { "ECB reference rates dated \($0.date)" } ?? "Waiting for ECB exchange rates")
                Spacer()
                TrendsActionButton(
                    title: "Sources",
                    systemImage: "sidebar.right",
                    tint: .blue,
                    action: onToggleSources
                )
                .accessibilityLabel(sourcesOpen ? "Hide sources" : "Show sources")
                .accessibilityValue(sourcesOpen ? "Open" : "Closed")
                TrendsActionButton(title: "Refresh", systemImage: "arrow.clockwise", action: onRefresh)
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
            if signals.isEmpty {
                VStack {
                    Spacer(minLength: 16)
                    if let activity {
                        RadarActivityBanner(activity: activity)
                            .frame(maxWidth: 440)
                    }
                    Text("Waiting for a confirmed rise or drop in minute candles")
                        .font(.title2.weight(.light))
                        .foregroundStyle(TrendsColors.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                    Spacer(minLength: 16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                                    currencyRates: currencyRates,
                                    displayCurrency: displayCurrency,
                                    compact: compact,
                                    isSelected: isSelected(item.signal),
                                    widths: widths,
                                    onSelect: { onSelect(item.signal) },
                                    onShowCoverage: { coverageRequest = $0 }
                                )
                                .accessibilityAddTraits(isSelected(item.signal) ? [.isSelected] : [])
                                .task(id: "\(item.signal.symbol)|\(scenePhase)") {
                                    guard scenePhase == .active else { return }
                                    await onVisibleSignal(item.signal.symbol)
                                }
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
        .padding(.vertical, 3)
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
            signals: signals, companyNames: names, currencyRates: currencyRates,
            displayCurrency: displayCurrency,
            fontSize: tableTypography.size
        )
        setWidth(contentWidths[column] ?? column.minimumWidth, for: column)
    }

    private func fittedWidths(availableWidth: CGFloat) -> RadarSignalColumnWidths {
        RadarSignalColumnWidths.fit(
            signals: signals,
            companyNames: signals.map { companyNames[$0.symbol] ?? $0.symbol },
            currencyRates: currencyRates,
            displayCurrency: displayCurrency,
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

private struct RadarSignalItem: Identifiable {
    let signal: ScanResult
    var id: String { "\(signal.symbol)|\(signal.signalSource)|\(signal.signalEpochMillis)" }
}
