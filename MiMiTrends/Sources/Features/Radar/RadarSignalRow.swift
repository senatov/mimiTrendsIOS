import SwiftUI

struct RadarSignalRow: View {
    @Environment(RadarTableColorStore.self) private var tableColors
    @Environment(\.colorScheme) private var colorScheme
    let signal: ScanResult
    let companyName: String
    let compact: Bool
    let isSelected: Bool
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
                RadarSignalColumnLines(color: tableColor(.grid), horizontalInset: 8)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(.default) { onSelect() }
    }

    private var compactContent: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(companyName).font(.body.weight(.light)).lineLimit(1)
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
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                eventBadge
                Spacer(minLength: 4)
                Link("Rumors", destination: rumorsURL)
                    .font(.subheadline)
                    .buttonStyle(TrendsActionButtonStyle(tint: tableColor(.actionAccent), compact: true))
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 6)
            .frame(width: 285)
            movement
                .padding(.horizontal, 6)
                .frame(width: 115, alignment: .trailing)
            Text(formattedPrice)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .frame(width: 70, alignment: .trailing)
            ageText
                .padding(.horizontal, 6)
                .frame(width: 50, alignment: .trailing)
        }
        .font(.body.weight(.light))
    }

    private var eventBadge: some View {
        Text(eventLabel)
            .font(.subheadline.weight(.light))
            .foregroundStyle(eventColor)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(eventColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
    }

    private var movement: some View {
        Text("\(signal.windowChangePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))))% / \(signal.signalWindowLabel)")
            .font(.body.weight(.light).monospacedDigit())
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
                .font(.subheadline.weight(.light).monospacedDigit())
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
}

struct RadarSignalColumnLines: View {
    let color: Color
    let horizontalInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for trailingWidth in [520.0, 235.0, 120.0, 50.0] {
                    let x = geometry.size.width - horizontalInset - CGFloat(trailingWidth)
                    guard x > horizontalInset else { continue }
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
