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
                        Text("Company").padding(.horizontal, 6).frame(maxWidth: .infinity, alignment: .leading)
                        Text("Event").padding(.horizontal, 6).frame(width: 285, alignment: .leading)
                        Text("Movement").padding(.horizontal, 6).frame(width: 115, alignment: .trailing)
                        Text("Price").padding(.horizontal, 6).frame(width: 70, alignment: .trailing)
                        Text("Age").padding(.horizontal, 6).frame(width: 50, alignment: .trailing)
                    }
                    .font(.subheadline.weight(.medium))
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
                        ForEach(signals.map(RadarSignalItem.init)) { item in
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

private struct RadarSignalItem: Identifiable {
    let signal: ScanResult
    var id: String { "\(signal.symbol)|\(signal.signalSource)|\(signal.signalEpochMillis)" }
}
