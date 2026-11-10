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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("PRICE HISTORY", systemImage: "chart.xyaxis.line")
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    identity
                }
                Spacer(minLength: 8)
                quote
                VStack(alignment: .trailing, spacing: 6) {
                    if hasTrades {
                        TrendsActionButton(title: "Trades", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                           tint: showingTrades ? .orange : .blue) { showingTrades.toggle() }
                            .accessibilityLabel("Show imported trades on the chart")
                            .accessibilityValue(showingTrades ? "On" : "Off")
                    }
                    TradeImportAction(title: "Import trades", onImport: onImport)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("VIEW")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
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
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Text("TIMEFRAME")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    Picker("Chart period", selection: $range) {
                        ForEach(RadarChartRange.allCases) { option in Text(option.title).tag(option) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 420)
                    Spacer(minLength: 0)
                }
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
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    Text(price.text).font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
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
                    .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
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
