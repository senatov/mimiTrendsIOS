import SwiftUI

struct RadarSignalList: View {
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
                    .foregroundStyle(TrendsColors.supportingInk)
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
                    .foregroundStyle(TrendsColors.supportingInk)
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(quoteMoves) { move in
                            HStack(spacing: 8) {
                                Text(move.quote.name)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(String(format: "%+.2f%%", move.changePercent))
                                    .foregroundStyle(move.changePercent < 0 ? .red : .green)
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
                    HStack(spacing: 8) {
                        Text("Company").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Event").frame(width: 285, alignment: .leading)
                        Text("Movement").frame(width: 115, alignment: .trailing)
                        Text("Price").frame(width: 70, alignment: .trailing)
                        Text("Age").frame(width: 50, alignment: .trailing)
                    }
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(TrendsColors.supportingInk)
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
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(TrendsColors.ink)
        .trendsPanel()
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
