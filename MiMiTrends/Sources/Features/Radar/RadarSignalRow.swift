import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RadarSignalRow: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let signal: ScanResult
    let companyName: String
    let compact: Bool
    let isSelected: Bool
    let widths: RadarSignalColumnWidths
    let onSelect: () -> Void

    var body: some View {
        Group {
            if compact {
                compactContent
            } else {
                wideContent
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay {
            if !compact {
                RadarSignalColumnLines(widths: widths, color: tableColor(.grid), horizontalInset: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onSelect() }
        .contextMenu {
            Button("Copy search keyword", systemImage: "doc.on.doc") {
                copy(RadarSearchKeyword.from(companyName: companyName, symbol: signal.symbol))
            }
            Button("Copy ticker", systemImage: "number") { copy(signal.symbol) }
            Button("Open Stock", systemImage: "chart.xyaxis.line", action: onSelect)
        }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(companyName).font(.system(size: 14, weight: .light)).lineLimit(1)
                Spacer()
                Text(formattedPrice).monospacedDigit()
            }
            HStack(spacing: 8) {
                eventBadge
                Spacer(minLength: 4)
                movement
            }
            ageText
        }
    }

    private var wideContent: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Text(companyName).lineLimit(1)
                Text("🇺🇸").accessibilityLabel("United States")
            }
            .padding(.horizontal, 6)
            .frame(width: widths.company, alignment: .leading)
            HStack(spacing: 6) {
                eventBadge
                Spacer(minLength: 4)
                Link("Rumors", destination: rumorsURL)
                    .font(.subheadline)
                    .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 6)
            .frame(width: widths.event)
            movement
                .padding(.horizontal, 6)
                .frame(width: widths.movement, alignment: .trailing)
            Text(formattedPrice)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(width: widths.price, alignment: .trailing)
            ageText
                .padding(.horizontal, 6)
                .frame(width: widths.age, alignment: .trailing)
        }
        .font(.system(size: 14, weight: .light))
    }

    private var eventBadge: some View {
        Text(eventLabel)
            .font(.subheadline)
            .foregroundStyle(eventColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(eventColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var movement: some View {
        Text("\(signal.windowChangePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))))% / \(signal.signalWindowLabel)")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(signal.windowChangePercent < 0 ? tableColor(.fall) : tableColor(.rise))
            .lineLimit(1)
    }

    private var eventLabel: String {
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

    private var eventColor: Color {
        if signal.signalSource.lowercased() == "tradable corridor" { return tableColor(.actionAccent) }
        return signal.windowChangePercent < 0 ? tableColor(.fall) : tableColor(.rise)
    }

    private var backgroundColor: Color {
        if signal.signalSource.lowercased() == "rapid crash" { return tableColor(.criticalRow) }
        return isSelected ? tableColor(.selectedRow) : Color.clear
    }

    private var savedAt: Date {
        Date(timeIntervalSince1970: TimeInterval(signal.signalEpochMillis) / 1_000)
    }

    private var ageText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(savedAt)))
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(tableColor(.mutedText))
        }
    }

    private var rumorsURL: URL {
        let symbol = signal.symbol.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? signal.symbol
        return URL(string: "https://finance.yahoo.com/quote/\(symbol)/news")!
    }

    private var formattedPrice: String {
        signal.price.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func tableColor(_ role: RadarTableColorRole) -> Color {
        tableColors.color(role, dark: colorScheme == .dark)
    }

    private func copy(_ value: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        #else
        UIPasteboard.general.string = value
        #endif
    }
}

enum RadarSearchKeyword {
    static func from(companyName: String, symbol: String) -> String {
        displayName(companyName, symbol: symbol) ??
            String(symbol.prefix(while: { $0 != "." })).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayName(_ companyName: String, symbol: String) -> String? {
        let source = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !source.isEmpty,
              source.caseInsensitiveCompare(symbol.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame else {
            return nil
        }

        var words = source
            .replacingOccurrences(of: "[,.;:()\\[\\]]+", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }

        while words.first?.caseInsensitiveCompare("The") == .orderedSame { words.removeFirst() }
        while words.last?.caseInsensitiveCompare("The") == .orderedSame { words.removeLast() }
        while let last = words.last, isRemovableSuffix(last) || last == "&" { words.removeLast() }

        let cleaned = words.joined(separator: " ")
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(where: \.isLowercase) { return cleaned }

        return words.map { word in
            let letters = word.filter(\.isLetter)
            guard letters.count > 3 else { return word }
            let lowercased = word.lowercased()
            return lowercased.prefix(1).uppercased() + lowercased.dropFirst()
        }.joined(separator: " ")
    }

    private static func isRemovableSuffix(_ word: String) -> Bool {
        let normalized = word.filter { $0.isLetter || $0.isNumber }.uppercased()
        return legalSuffixes.contains(normalized) ||
            normalized.range(of: "^[A-Z0-9]$", options: .regularExpression) != nil ||
            normalized.range(of: "^(ACT|ACTION|ORD|ORDINARY)[A-Z0-9]?$", options: .regularExpression) != nil
    }

    private static let legalSuffixes: Set<String> = [
        "AG", "SE", "INC", "INCORPORATED", "CORP", "CORPORATION", "PLC", "LTD", "LIMITED",
        "SA", "SAS", "SPA", "NV", "BV", "GMBH", "KG", "KGAA", "CO", "COMPANY"
    ]
}

struct RadarSignalColumnLines: View {
    let widths: RadarSignalColumnWidths
    let color: Color
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                var x = horizontalInset + widths.company
                for width in [widths.event, widths.movement, widths.price] {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                    x += width
                }
            }
            .stroke(color, lineWidth: 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
