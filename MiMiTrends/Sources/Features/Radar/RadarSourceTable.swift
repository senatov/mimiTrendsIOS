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
    private let widths: [RadarSourceSortColumn: CGFloat]
    let table: CGFloat

    func width(for column: RadarSourceSortColumn) -> CGFloat {
        widths[column] ?? 0
    }

    static func fit(sources: [RadarTelemetrySource], availableWidth: CGFloat,
                    fontName: String, fontSize: CGFloat) -> Self {
        var widths: [RadarSourceSortColumn: CGFloat] = [:]
        for column in RadarSourceSortColumn.allCases {
            let heading = measure([column.title.uppercased()], fontName: fontName, fontSize: fontSize) + 29
            let content: CGFloat
            switch column {
            case .source:
                content = measure(sources.map(\.name), fontName: fontName, fontSize: fontSize) +
                    (sources.contains { $0.canShowCandidates } ? 53 : 18)
            case .status:
                content = measure(sources.map { $0.status.uppercased() }, fontName: fontName,
                                  fontSize: fontSize) + 14
            default:
                content = measure(sources.compactMap { $0.value(for: column)?.formatted() },
                                  fontName: fontName, fontSize: fontSize) + 18
            }
            widths[column] = max(column == .source ? 100 : 48, max(heading, content))
        }
        let minimumWidth = RadarSourceSortColumn.allCases.reduce(CGFloat(14)) { $0 + (widths[$1] ?? 0) }
        let spare = max(0, availableWidth - minimumWidth)
        widths[.source, default: 0] += spare * 0.6
        widths[.status, default: 0] += spare * 0.4
        return Self(widths: widths, table: minimumWidth + spare)
    }

    private static func measure(_ values: [String], fontName: String, fontSize: CGFloat) -> CGFloat {
        #if os(macOS)
        let font = NSFont(name: fontName, size: fontSize) ?? NSFont.systemFont(ofSize: fontSize)
        #else
        let font = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
        #endif
        return values.prefix(200).map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
    }
}

struct RadarSourceTable: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    let sources: [RadarTelemetrySource]
    let availableWidth: CGFloat
    let onShowCandidates: () -> Void

    @State private var sortColumn: RadarSourceSortColumn?
    @State private var ascending = true

    private var layout: RadarSourceTableLayout {
        RadarSourceTableLayout.fit(sources: sources, availableWidth: availableWidth,
                                   fontName: tableTypography.fontName,
                                   fontSize: CGFloat(tableTypography.size))
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
                        onShowCandidates: onShowCandidates
                    )
                    separator
                }
            }
            .frame(width: layout.table, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var headings: some View {
        HStack(spacing: 0) {
            ForEach(RadarSourceSortColumn.allCases, id: \.self) { column in
                heading(column)
                    .frame(width: layout.width(for: column))
            }
        }
        .font(tableTypography.font(size: tableTypography.size))
        .foregroundStyle(tableColor(.sourceHeaderText))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(tableColor(.sourceHeaderFill))
        .overlay {
            RadarSourceColumnLines(layout: layout, color: tableColor(.sourceGrid), inset: 7)
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
                    .foregroundStyle(sortColumn == column ? Color.white : tableColor(.sourceHeaderText))
                    .frame(width: 16, height: 16)
                    .background(sortColumn == column ? tableColor(.sourceActionAccent) : tableColor(.sourceHeaderFill), in: Circle())
                    .overlay { Circle().strokeBorder(tableColor(.sourceHeaderText).opacity(0.3), lineWidth: 0.6) }
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
        Rectangle().fill(tableColor(.sourceGrid)).frame(height: 1).accessibilityHidden(true)
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }
}

private struct RadarSourceTelemetryRow: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    let source: RadarTelemetrySource
    let layout: RadarSourceTableLayout
    let onShowCandidates: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sourceCell.frame(width: layout.width(for: .source), alignment: .leading)
            metric(source.received).frame(width: layout.width(for: .received), alignment: .trailing)
            metric(source.valid).frame(width: layout.width(for: .valid), alignment: .trailing)
            metric(source.requests).frame(width: layout.width(for: .requests), alignment: .trailing)
            metric(source.errors).frame(width: layout.width(for: .errors), alignment: .trailing)
            Text(source.status.uppercased())
                .font(tableTypography.font(size: tableTypography.size))
                .foregroundStyle(source.statusColor)
                .lineLimit(1)
                .frame(width: layout.width(for: .status), alignment: .trailing)
        }
        .font(tableTypography.font(size: tableTypography.size))
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .overlay { RadarSourceColumnLines(layout: layout, color: tableColor(.sourceGrid), inset: 7) }
        .background(tableColor(.sourceRowFill))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("source-\(source.name)")
    }

    private var sourceCell: some View {
        HStack(spacing: 6) {
            Circle().fill(source.dotColor).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(source.name).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 2)
            if source.canShowCandidates {
                Button(action: onShowCandidates) {
                    Image(systemName: "list.number")
                }
                .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.sourceActionAccent), compact: true))
                .accessibilityLabel("View ranking candidates")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
    }

    private func metric(_ value: Int?) -> some View {
        Text(value.map { $0.formatted() } ?? "—")
            .font(tableTypography.font(size: tableTypography.size).monospacedDigit())
            .foregroundStyle(tableColor(.sourceBodyText))
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
                var x = inset
                for column in RadarSourceSortColumn.allCases.dropLast() {
                    x += layout.width(for: column)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                }
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
