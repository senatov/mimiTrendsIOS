import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RadarTelemetrySource: Identifiable {
    let name: String
    let status: String
    let statusColor: Color
    let dotColor: Color
    let received: Int?
    let valid: Int?
    let requests: Int?
    let errors: Int?
    let canLogin: Bool
    let canShowCandidates: Bool

    var id: String { name }

    func value(for column: RadarSourceSortColumn) -> Int? {
        switch column {
        case .received: received
        case .valid: valid
        case .requests: requests
        case .errors: errors
        default: nil
        }
    }
}

enum RadarSourceSortColumn: CaseIterable {
    case source, received, valid, requests, errors, status

    var title: String {
        switch self {
        case .source: "Source"
        case .received: "Recv"
        case .valid: "Valid"
        case .requests: "Req"
        case .errors: "Err"
        case .status: "Status"
        }
    }

    var isNumeric: Bool {
        self == .received || self == .valid || self == .requests || self == .errors
    }
}

struct RadarSourceTableLayout {
    let source: CGFloat
    let metric: CGFloat
    let status: CGFloat
    let table: CGFloat

    func width(for column: RadarSourceSortColumn) -> CGFloat {
        switch column {
        case .source: source
        case .received, .valid, .requests, .errors: metric
        case .status: status
        }
    }

    static func fit(sources: [RadarTelemetrySource], availableWidth: CGFloat) -> Self {
        let sourceWidth = max(138, measure(sources.map(\.name)) + 34)
        let statusWidth = max(150, measure(sources.map(\.status)) + 34)
        let counts = sources.flatMap { [$0.received, $0.valid, $0.requests, $0.errors].compactMap { $0 } }
        let metricWidth = max(68, measure(counts.map { $0.formatted() }) + 28)
        let minimumTableWidth = sourceWidth + metricWidth * 4 + statusWidth + 14
        let tableWidth = max(availableWidth, minimumTableWidth)
        let fittedSourceWidth = max(sourceWidth, tableWidth - metricWidth * 4 - statusWidth - 14)
        return Self(source: fittedSourceWidth, metric: metricWidth, status: statusWidth, table: tableWidth)
    }

    private static func measure(_ values: [String]) -> CGFloat {
        #if os(macOS)
        let font = NSFont.systemFont(ofSize: 12)
        #else
        let font = UIFont.systemFont(ofSize: 12)
        #endif
        return values.prefix(200).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }
}

struct RadarSourceTable: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let sources: [RadarTelemetrySource]
    let availableWidth: CGFloat
    let onLogin: () -> Void
    let onShowCandidates: () -> Void

    @State private var sortColumn: RadarSourceSortColumn?
    @State private var ascending = true

    private var layout: RadarSourceTableLayout {
        RadarSourceTableLayout.fit(sources: sources, availableWidth: availableWidth)
    }

    private var sortedSources: [RadarTelemetrySource] {
        guard let sortColumn else { return sources }
        return sources.sorted { left, right in
            let result: ComparisonResult
            if sortColumn.isNumeric {
                switch (left.value(for: sortColumn), right.value(for: sortColumn)) {
                case let (leftValue?, rightValue?):
                    if leftValue == rightValue { result = .orderedSame }
                    else { result = leftValue < rightValue ? .orderedAscending : .orderedDescending }
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    result = .orderedSame
                }
            } else {
                let leftText = sortColumn == .source ? left.name : left.status
                let rightText = sortColumn == .source ? right.name : right.status
                result = leftText.localizedStandardCompare(rightText)
            }
            if result == .orderedSame { return left.name < right.name }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                headings
                ForEach(sortedSources) { source in
                    RadarSourceTelemetryRow(
                        source: source,
                        layout: layout,
                        onLogin: onLogin,
                        onShowCandidates: onShowCandidates
                    )
                    separator
                }
            }
            .frame(width: layout.table, alignment: .leading)
        }
    }

    private var headings: some View {
        HStack(spacing: 0) {
            ForEach(RadarSourceSortColumn.allCases, id: \.self) { column in
                heading(column)
                    .frame(width: layout.width(for: column))
            }
        }
        .font(.system(size: 12, weight: .regular))
        .foregroundStyle(tableColor(.headerText))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(tableColor(.headerFill))
        .overlay {
            RadarSourceColumnLines(layout: layout, color: tableColor(.grid), inset: 7)
        }
        .overlay(alignment: .bottom) { separator }
    }

    private func heading(_ column: RadarSourceSortColumn) -> some View {
        HStack(spacing: 3) {
            Text(column.title.uppercased())
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: column.isNumeric ? .trailing : .leading)
            Button { toggleSort(column) } label: {
                Image(systemName: arrowName(for: column))
                    .font(.system(size: sortColumn == column ? 8 : 7, weight: .semibold))
                    .foregroundStyle(sortColumn == column ? Color.white : tableColor(.headerText))
                    .frame(width: 16, height: 16)
                    .background(sortColumn == column ? tableColor(.actionAccent) : tableColor(.headerFill), in: Circle())
                    .overlay { Circle().strokeBorder(tableColor(.headerText).opacity(0.3), lineWidth: 0.6) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sort by \(column.title)")
            .accessibilityValue(sortColumn == column ? (ascending ? "Ascending" : "Descending") : "Unsorted")
        }
        .padding(.horizontal, 5)
    }

    private func toggleSort(_ column: RadarSourceSortColumn) {
        if sortColumn == column { ascending.toggle() }
        else {
            sortColumn = column
            ascending = column.isNumeric ? false : true
        }
    }

    private func arrowName(for column: RadarSourceSortColumn) -> String {
        guard sortColumn == column else { return "arrow.up.arrow.down" }
        return ascending ? "chevron.up" : "chevron.down"
    }

    private var separator: some View {
        Rectangle().fill(tableColor(.grid)).frame(height: 1).accessibilityHidden(true)
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }
}

private struct RadarSourceTelemetryRow: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let source: RadarTelemetrySource
    let layout: RadarSourceTableLayout
    let onLogin: () -> Void
    let onShowCandidates: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sourceCell.frame(width: layout.source, alignment: .leading)
            metric(source.received).frame(width: layout.metric, alignment: .trailing)
            metric(source.valid).frame(width: layout.metric, alignment: .trailing)
            metric(source.requests).frame(width: layout.metric, alignment: .trailing)
            metric(source.errors).frame(width: layout.metric, alignment: .trailing)
            Text(source.status.uppercased())
        .font(.system(size: 12, weight: .regular))
                .foregroundStyle(source.statusColor)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(width: layout.status, alignment: .trailing)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .overlay { RadarSourceColumnLines(layout: layout, color: tableColor(.grid), inset: 7) }
        .background(tableColor(.bodyText).opacity(0.025))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-\(source.name)")
    }

    private var sourceCell: some View {
        HStack(spacing: 6) {
            Circle().fill(source.dotColor).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(source.name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            if source.canLogin {
                Button("Login", action: onLogin)
                    .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
            } else if source.canShowCandidates {
                Button(action: onShowCandidates) {
                    Image(systemName: "list.number")
                }
                .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
                .accessibilityLabel("View ranking candidates")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func metric(_ value: Int?) -> some View {
        Text(value.map { $0.formatted() } ?? "—")
            .font(.system(size: 13).monospacedDigit())
            .foregroundStyle(tableColor(.bodyText))
            .lineLimit(1)
            .padding(.trailing, 5)
            .accessibilityLabel(value.map(String.init) ?? "unavailable")
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }
}

private struct RadarSourceColumnLines: View {
    let layout: RadarSourceTableLayout
    let color: Color
    let inset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                var x = inset + layout.source
                for _ in 0..<4 {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    x += layout.metric
                }
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
