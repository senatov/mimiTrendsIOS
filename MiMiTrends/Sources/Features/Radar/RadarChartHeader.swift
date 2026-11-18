import SwiftUI

struct RadarChartHeader: View {
    let symbol: String
    let companyName: String
    let metadata: RadarCompanyMetadata?
    let signal: ScanResult?
    let eventBar: MinuteBar?
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
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    instrumentSummary(compact: false)
                        .fixedSize(horizontal: true, vertical: false)
                    chartControls(showTitles: true)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    instrumentSummary(compact: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    chartControls(showTitles: false)
                }
            }
            .padding(.vertical, 4)
            if let event = eventBar {
                let direction = event.close > event.open ? "↑" : event.close < event.open ? "↓" : "→"
                let time = Date(timeIntervalSince1970: TimeInterval(event.minuteEpochSeconds))
                    .formatted(date: .abbreviated, time: .shortened)
                Text("Event candle \(time) \(direction) · O \(event.open.formatted(.number.precision(.fractionLength(2)))) · H \(event.high.formatted(.number.precision(.fractionLength(2)))) · L \(event.low.formatted(.number.precision(.fractionLength(2)))) · C \(event.close.formatted(.number.precision(.fractionLength(2)))) · Volume \(Int(event.volume).formatted())")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Event candle \(time), \(direction == "↑" ? "up" : direction == "↓" ? "down" : "flat"). Open \(event.open), high \(event.high), low \(event.low), close \(event.close), volume \(Int(event.volume))")
                if let turnover = signal?.recentTurnover {
                    Text("30-minute turnover \(turnover.formatted(.currency(code: signal?.priceCurrency ?? "USD")))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
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

    private func instrumentSummary(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            identity(compact: compact)
            quote(compact: compact)
        }
        .lineLimit(1)
    }

    private func chartControls(showTitles: Bool) -> some View {
        HStack(spacing: 16) {
            TrendsActionButton(title: "Signal focus", systemImage: "scope",
                               showsTitle: showTitles, glass: true,
                               tint: showingSignalFocus && focusAvailable ? .purple : .blue) {
                showingSignalFocus = true
            }
            .disabled(!focusAvailable)
            .accessibilityValue(showingSignalFocus && focusAvailable ? "Selected" : "Not selected")
            TrendsActionButton(title: "Full history", systemImage: "chart.xyaxis.line",
                               showsTitle: showTitles, glass: true,
                               tint: showingSignalFocus && focusAvailable ? .blue : .purple) {
                showingSignalFocus = false
            }
            Menu {
                ForEach(RadarChartRange.allCases) { option in
                    Button {
                        range = option
                    } label: {
                        if range == option {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Text(option.title)
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(range.title).monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .glassEffect(.regular, in: Capsule())
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Chart period")
            .accessibilityValue(range.title)
            if hasTrades {
                TrendsActionButton(title: "Trades", systemImage: "point.topleft.down.curvedto.point.bottomright.up",
                                   showsTitle: showTitles, glass: true,
                                   tint: showingTrades ? .orange : .blue) { showingTrades.toggle() }
                    .accessibilityLabel("Show imported trades on the chart")
                    .accessibilityValue(showingTrades ? "On" : "Off")
            }
            TradeImportAction(title: "Import trades", showsTitle: showTitles, glass: true, onImport: onImport)
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func identity(compact: Bool) -> some View {
        HStack(spacing: compact ? 6 : 10) {
            if !symbol.isEmpty {
                RadarCompanyMark(metadata: metadata, name: companyName, size: 22, showsPlaceholder: true)
            }
            HStack(alignment: .center, spacing: compact ? 5 : 8) {
                if let flag = RadarCompanyMetadata.flag(for: RadarCompanyMetadata.listingCountry(for: symbol)) {
                    Text(flag).accessibilityLabel("Listing country")
                }
                Text(symbol.isEmpty ? "No symbol selected" : companyName)
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
                HStack(spacing: 8) {
                    Text(symbol).font(.system(.caption, design: .monospaced).weight(.medium))
                        .foregroundStyle(.indigo)
                    if !compact { Text(currency).font(.caption).foregroundStyle(.secondary) }
                }
            }
        }
    }

    @ViewBuilder
    private func quote(compact: Bool) -> some View {
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
                if compact {
                    compactStatus(signal.currentPrice == nil ? "Event" : "Latest",
                                  epoch: (signal.currentPriceAtMillis ?? signal.signalEpochMillis) / 1_000)
                } else {
                    Text(RadarSignalPresentation.title(for: signal.signalSource))
                        .font(.caption).foregroundStyle(.indigo)
                    status(signal.currentPrice == nil ? "Event price" : "Latest \(signal.currentPriceSource ?? "price")",
                           epoch: (signal.currentPriceAtMillis ?? signal.signalEpochMillis) / 1_000)
                }
            }
        } else if let lastBar {
            HStack(alignment: .center, spacing: 8) {
                Text(lastBar.close, format: .currency(code: currency).precision(.fractionLength(2)))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                if compact {
                    compactStatus("Saved close", epoch: lastBar.minuteEpochSeconds)
                } else {
                    status("Saved close", epoch: lastBar.minuteEpochSeconds)
                }
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

    private func compactStatus(_ title: String, epoch: Int64) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.purple.opacity(0.09), in: Capsule())
            .help("\(title) · \(Date(timeIntervalSince1970: Double(epoch)).formatted(.dateTime.day().month().hour().minute()))")
    }
}
