import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct RadarSignalRow: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(RadarTableTypographyStore.self) private var tableTypography
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("controls.button.iconColor.v1") private var actionIconColor = ""
    let signal: ScanResult
    let companyName: String
    let companyMetadata: RadarCompanyMetadata?
    let currencyRates: DisplayCurrencyRates?
    let displayCurrency: String
    let compact: Bool
    var isOld: Bool = false
    let isSelected: Bool
    let widths: RadarSignalColumnWidths
    let onSelect: () -> Void
    let onShowCoverage: (RadarCoverageRequest) -> Void

    var body: some View {
        Group {
            if compact {
                compactContent
            } else {
                wideContent
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay {
            if !compact {
                RadarSignalColumnLines(widths: widths, color: tableColor(.signalGrid), horizontalInset: 8)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(companyName), \(signal.symbol)")
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
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                companyIdentity
                    .layoutPriority(1)
                Spacer()
                Text(formattedPrice.text).monospacedDigit()
                    .help(formattedPrice.explanation)
            }
            HStack(spacing: 8) {
                eventBadge
                Spacer(minLength: 4)
                movement
                windowText
            }
            ageText
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var wideContent: some View {
        HStack(spacing: 0) {
            companyIdentity
            .padding(.horizontal, 6)
            .frame(width: widths.company, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            HStack(spacing: 6) {
                eventBadge
                    .onTapGesture(perform: onSelect)
                Spacer(minLength: 4)
                Button {
                    onShowCoverage(RadarCoverageRequest(symbol: signal.symbol, companyName: companyName))
                } label: {
                    Image(systemName: "ear")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(RadarColorHex.color(actionIconColor) ?? tableColor(.signalActionAccent))
                }
                .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.signalActionAccent), compact: true, tiny: true))
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("Rumors for \(signal.symbol)")
                .accessibilityHint("Show recent news and Reuters search")
                .help("Rumors for \(signal.symbol)")
            }
            .padding(.leading, 6)
            .padding(.trailing, 16)
            .frame(width: widths.event)
            movement
                .padding(.horizontal, 6)
                .frame(width: widths.movement, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            windowText
                .padding(.horizontal, 6)
                .frame(width: widths.window, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            Text(formattedPrice.text)
                .monospacedDigit()
                .help(formattedPrice.explanation)
                .padding(.horizontal, 6)
                .frame(width: widths.price, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
            ageText
                .padding(.horizontal, 6)
                .frame(width: widths.age, alignment: .trailing)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
        }
        .font(tableTypography.font(size: tableTypography.size))
    }

    private var companyIdentity: some View {
        HStack(spacing: 5) {
            RadarCompanyMark(metadata: companyMetadata, name: companyName, showsPlaceholder: true)
            Text(companyName).lineLimit(1)
            if let flag = RadarCompanyMetadata.flag(for: companyMetadata?.countryCode ?? RadarCompanyMetadata.countryFallback(for: signal.symbol)) {
                Text(flag).accessibilityLabel("Issuer country")
            }
        }
    }

    private var eventBadge: some View {
        Text(eventLabel)
            .font(tableTypography.font(size: max(10, tableTypography.size - 1)))
            .foregroundStyle(eventColor)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(eventColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var movement: some View {
        Text("\(signal.windowChangePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))))%")
            .font(tableTypography.font(size: tableTypography.size * 0.86).monospacedDigit())
            .foregroundStyle(signal.windowChangePercent < 0 ? tableColor(.fall) : tableColor(.rise))
            .lineLimit(1)
    }

    private var windowText: some View {
        Text(signal.signalWindowLabel)
            .font(tableTypography.font(size: tableTypography.size * 0.86).monospacedDigit())
            .foregroundStyle(tableColor(.signalMutedText))
            .lineLimit(1)
    }

    private var eventLabel: String {
        let label = RadarSignalPresentation.badge(for: signal.signalSource)
        return signal.isRetained ? "\(label) · RECENT" : label
    }

    private var eventColor: Color {
        if signal.signalSource.lowercased() == "tradable corridor" { return tableColor(.signalActionAccent) }
        return signal.windowChangePercent < 0 ? tableColor(.fall) : tableColor(.rise)
    }

    private var backgroundColor: Color {
        if signal.signalSource.lowercased() == "rapid crash" { return tableColor(.criticalRow) }
        return isSelected ? tableColor(.selectedRow) : tableColor(.signalRowFill)
    }

    private var savedAt: Date {
        Date(timeIntervalSince1970: TimeInterval(signal.signalEpochMillis) / 1_000)
    }

    private var ageText: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(savedAt)))
            Text(isOld
                 ? String(format: "(OLD) %02d:%02d H", seconds / 3_600, (seconds / 60) % 60)
                 : String(format: "%@%02d:%02d", MarketCandidateFilter.isGermanSymbol(signal.symbol) ? "(DELAYED) " : "", seconds / 60, seconds % 60))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .font(tableTypography.font(size: tableTypography.size * 0.86).monospacedDigit())
                .foregroundStyle(tableColor(.signalMutedText))
        }
    }

    private var formattedPrice: RadarSignalPrice.Presentation {
        RadarSignalPrice.display(signal, rates: currencyRates, currency: displayCurrency)
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
            .filter { $0.caseInsensitiveCompare("com") != .orderedSame }

        while words.first?.caseInsensitiveCompare("The") == .orderedSame { words.removeFirst() }
        while words.last?.caseInsensitiveCompare("The") == .orderedSame { words.removeLast() }
        while let last = words.last, isRemovableSuffix(last) || last == "&" { words.removeLast() }

        // Long hyphenated legal names often contain several administrative words
        // that make a poor web search. The first name is a useful keyword here.
        if words.contains(where: { $0.contains("-") && $0.count >= 16 }), let first = words.first {
            return first
        }

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

    static func cleanedCompanyName(_ companyName: String, symbol: String) -> String {
        displayName(companyName, symbol: symbol) ?? companyName.trimmingCharacters(in: .whitespacesAndNewlines)
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
                for width in [widths.event, widths.movement, widths.window, widths.price] {
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
