import SwiftUI

struct RadarChartHeader: View {
    let symbol: String
    let companyName: String
    let metadata: RadarCompanyMetadata?
    let signal: ScanResult?
    let lastBar: MinuteBar?
    let rates: DisplayCurrencyRates?
    let currency: String
    let hasTrades: Bool
    let outsideTradeCount: Int
    @Binding var showingTrades: Bool
    @Binding var range: RadarChartRange
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Price chart", systemImage: "chart.xyaxis.line")
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
                    .foregroundStyle(.indigo)
                Spacer(minLength: 8)
                if hasTrades {
                    TrendsActionButton(title: "Trades", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                       tint: showingTrades ? .orange : .blue) { showingTrades.toggle() }
                        .accessibilityLabel("Show imported trades on the chart")
                        .accessibilityValue(showingTrades ? "On" : "Off")
                }
                TradeImportAction(title: "Import trades", onImport: onImport)
            }
            Divider()
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 24) {
                    identity
                    Spacer(minLength: 12)
                    quote
                }
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    quote
                }
            }
            HStack(spacing: 12) {
                Text("Period").font(.caption).foregroundStyle(.secondary)
                Picker("Chart period", selection: $range) {
                    ForEach(RadarChartRange.allCases) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
                Spacer(minLength: 0)
            }
            if hasTrades && outsideTradeCount > 0 && range != .trades {
                HStack(spacing: 10) {
                    Text("\(outsideTradeCount) imported \(outsideTradeCount == 1 ? "trade" : "trades") outside \(range.title)")
                        .font(.caption).foregroundStyle(.secondary)
                    TrendsActionButton(title: "Show trade history", systemImage: "clock.arrow.circlepath", tint: .purple) {
                        range = .trades
                        showingTrades = true
                    }
                }
            }
        }
    }

    private var identity: some View {
        HStack(spacing: 10) {
            if !symbol.isEmpty {
                RadarCompanyMark(metadata: metadata, name: companyName, size: 30, showsPlaceholder: true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(symbol.isEmpty ? "No symbol selected" : companyName)
                    .font(.system(.title3, design: .rounded).weight(.regular))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Text(symbol).font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.indigo)
                    Text(currency).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var quote: some View {
        if let signal {
            let price = RadarSignalPrice.display(signal, rates: rates, currency: currency)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(price.text).font(.system(.title2, design: .rounded).monospacedDigit())
                        .foregroundStyle(.primary).help(price.explanation)
                    Text(signal.windowChangePercent.formatted(.number.sign(strategy: .always()).precision(.fractionLength(2))) + "%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(signal.windowChangePercent < 0 ? .red : .green)
                }
                Text(RadarSignalPresentation.title(for: signal.signalSource))
                    .font(.caption).foregroundStyle(.indigo)
                status(signal.dataStatus == "DELAYED" ? "Delayed signal" : "Signal price",
                       epoch: signal.signalEpochMillis / 1_000)
            }
        } else if let lastBar {
            VStack(alignment: .trailing, spacing: 4) {
                Text(lastBar.close, format: .currency(code: currency).precision(.fractionLength(2)))
                    .font(.system(.title2, design: .rounded).monospacedDigit())
                    .foregroundStyle(.primary)
                status("Saved close", epoch: lastBar.minuteEpochSeconds)
            }
        }
    }

    private func status(_ title: String, epoch: Int64) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption.weight(.regular))
                .foregroundStyle(.purple)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(.purple.opacity(0.09), in: Capsule())
            Text(Date(timeIntervalSince1970: Double(epoch)), format: .dateTime.day().month().hour().minute())
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}
