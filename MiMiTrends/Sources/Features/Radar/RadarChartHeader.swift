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
    let focusAvailable: Bool
    @Binding var showingTrades: Bool
    @Binding var showingSignalFocus: Bool
    @Binding var range: RadarChartRange
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    identity
                    quote
                    Divider().frame(height: 20)
                    TrendsActionButton(title: "Signal focus", systemImage: "scope",
                                       tint: showingSignalFocus && focusAvailable ? .purple : .blue) {
                        showingSignalFocus = true
                    }
                    .disabled(!focusAvailable)
                    .accessibilityValue(showingSignalFocus && focusAvailable ? "Selected" : "Not selected")
                    TrendsActionButton(title: "Full history", systemImage: "chart.xyaxis.line",
                                       tint: showingSignalFocus && focusAvailable ? .blue : .purple) {
                        showingSignalFocus = false
                    }
                    Picker("Chart period", selection: $range) {
                        ForEach(RadarChartRange.allCases) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                    if hasTrades {
                        TrendsActionButton(title: "Trades", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                           tint: showingTrades ? .orange : .blue) { showingTrades.toggle() }
                            .accessibilityLabel("Show imported trades on the chart")
                            .accessibilityValue(showingTrades ? "On" : "Off")
                    }
                    TradeImportAction(title: "Import trades", onImport: onImport)
                }
                .lineLimit(1)
                .frame(minHeight: 32)
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
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
                RadarCompanyMark(metadata: metadata, name: companyName, size: 22, showsPlaceholder: true)
            }
            HStack(alignment: .center, spacing: 8) {
                Text(symbol.isEmpty ? "No symbol selected" : companyName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
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
            HStack(alignment: .center, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(price.text).font(.headline.monospacedDigit())
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
            HStack(alignment: .center, spacing: 8) {
                Text(lastBar.close, format: .currency(code: currency).precision(.fractionLength(2)))
                    .font(.headline.monospacedDigit())
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
