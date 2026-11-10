import Charts
import SwiftUI

struct RadarChartPlot: View {
    let data: RadarChartData
    let symbol: String
    let displayCurrency: String
    let signal: ScanResult?
    let signalEntryPrice: Double?
    let trades: [BrokerTradePosition]
    var priceHeight: CGFloat = 300
    var volumeHeight: CGFloat = 90
    @Binding var inspection: RadarChartInspection?
    @State private var selectedMinute: Int64?
    @State private var selectedPrice: Double?
    @State private var cursorPinned = false
    @State private var plotWidth: CGFloat = 800
    @State private var tradeAnchors: [String: CGPoint] = [:]

    private var timeline: RadarChartTimeline { RadarChartTimeline(bars: data.bars) }

    private var selectedBar: MinuteBar? {
        guard let selectedMinute else { return nil }
        return data.bars.first { $0.minuteEpochSeconds == selectedMinute }
    }

    private var visibleTrades: [BrokerTradePosition] {
        guard let first = data.bars.first?.minuteEpochSeconds,
              let last = data.bars.last?.minuteEpochSeconds else { return [] }
        return trades.filter { trade in
            trade.entryEpochSeconds <= last && (trade.exitEpochSeconds ?? Int64.max) >= first
        }.suffix(100).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                if let signal, let signalEntryPrice, signalIsVisible(signal) {
                    let startEpoch = max(
                        data.bars.first?.minuteEpochSeconds ?? 0,
                        signal.signalEpochMillis / 1_000 - signalWindowMinutes(signal) * 60
                    )
                    let endEpoch = signal.signalEpochMillis / 1_000
                    RectangleMark(
                        xStart: .value("Signal start", timeline.position(startEpoch)),
                        xEnd: .value("Signal end", timeline.position(endEpoch)),
                        yStart: .value("Signal low", priceDomain.lowerBound),
                        yEnd: .value("Signal high", priceDomain.upperBound)
                    )
                    .foregroundStyle(.orange.opacity(0.08))
                    RuleMark(y: .value("Signal entry", signalEntryPrice))
                        .foregroundStyle(.orange.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
                }
                ForEach(data.bars, id: \.minuteEpochSeconds) { bar in
                    let time = timeline.position(bar.minuteEpochSeconds)
                    let halfWidth: TimeInterval = 20
                    let rising = bar.close >= bar.open
                    let color = rising ? RadarCandleVisualStyle.rise : RadarCandleVisualStyle.fall
                    RuleMark(
                        x: .value("Minute", time),
                        yStart: .value("Low", bar.low),
                        yEnd: .value("High", bar.high)
                    )
                    .foregroundStyle(color)
                    .accessibilityLabel(Text(bar.chartDate.formatted(.dateTime.day().month().hour().minute())))
                    RectangleMark(
                        xStart: .value("Start", time - halfWidth),
                        xEnd: .value("End", time + halfWidth),
                        yStart: .value("Open", bar.open),
                        yEnd: .value("Close", bar.close)
                    )
                    .foregroundStyle(RadarCandleVisualStyle.body(rising: rising))
                    .alignsMarkStylesWithPlotArea(false)
                    .accessibilityLabel(Text(bar.chartDate.formatted(.dateTime.day().month().hour().minute())))
                }
                ForEach(data.fastEMA) { point in
                    LineMark(x: .value("Minute", timeline.position(point.minuteEpochSeconds)),
                             y: .value("EMA 9 depth", point.value),
                             series: .value("Overlay segment", "EMA 9 depth"))
                        .foregroundStyle(RadarCandleVisualStyle.fastLine.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    LineMark(
                        x: .value("Minute", timeline.position(point.minuteEpochSeconds)),
                        y: .value("EMA 9", point.value),
                        series: .value("Overlay segment", "EMA 9")
                    )
                    .foregroundStyle(RadarCandleVisualStyle.fastLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                }
                ForEach(data.slowEMA) { point in
                    LineMark(x: .value("Minute", timeline.position(point.minuteEpochSeconds)),
                             y: .value("EMA 21 depth", point.value),
                             series: .value("Overlay segment", "EMA 21 depth"))
                        .foregroundStyle(RadarCandleVisualStyle.slowLine.opacity(0.15))
                        .lineStyle(StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                    LineMark(
                        x: .value("Minute", timeline.position(point.minuteEpochSeconds)),
                        y: .value("EMA 21", point.value),
                        series: .value("Overlay segment", "EMA 21")
                    )
                    .foregroundStyle(RadarCandleVisualStyle.slowLine)
                    .lineStyle(StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                }
                ForEach(data.trend30) { point in
                    LineMark(
                        x: .value("Minute", timeline.position(point.minuteEpochSeconds)),
                        y: .value("Trend 30", point.value),
                        series: .value("Overlay", "Trend 30")
                    )
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [6, 4]))
                }
                if let last = data.bars.last {
                    RuleMark(y: .value("Current price", last.close))
                        .foregroundStyle(.teal.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 3]))

                }
                ForEach(visibleTrades) { trade in
                    tradeMarks(for: trade)
                }
                if let selectedBar, let selectedPrice {
                    RuleMark(x: .value("Selected time", timeline.position(selectedBar.minuteEpochSeconds)))
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    RuleMark(y: .value("Selected price", selectedPrice))
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .accessibilityLabel("\(data.range.usesDailyBars ? "Daily" : "Minute") candle chart with EMA 9 and EMA 21 for \(symbol)")
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { plotWidth = $0 }
            .chartPlotStyle { plot in
                plot.background(.background.opacity(0.65))
                    .overlay(Rectangle().stroke(.secondary.opacity(0.12), lineWidth: 0.5))
            }
            .chartYScale(domain: priceDomain)
            .chartXScale(domain: timeline.domain)
            .chartXAxis { timelineAxis }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                    AxisTick()
                    AxisValueLabel {
                        if let price = value.as(Double.self) {
                            Text(price.formatted(.currency(code: displayCurrency).precision(.fractionLength(2))))
                                .font(.caption2.monospacedDigit())
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                ZStack {
                    if selectedBar == nil, let last = data.bars.last {
                        RadarChartLastPriceLabel(proxy: proxy, price: last.close, currency: displayCurrency)
                    }
                    RadarChartCursorOverlay(
                    proxy: proxy, bars: data.bars, timeline: timeline, displayCurrency: displayCurrency, readsPrice: true,
                    selectedBar: selectedBar, selectedPrice: selectedPrice,
                    isPinned: cursorPinned, onSelection: select(bar:price:),
                    onTogglePin: toggleCursorPin, onExit: clearCursor
                )
                    RadarTradeAnchorReader(proxy: proxy, timeline: timeline, trades: visibleTrades)
                }
            }
            .frame(height: priceHeight)
            .animation(.easeInOut(duration: 0.24), value: data.bars.map(\.minuteEpochSeconds))
            .animation(.easeInOut(duration: 0.16), value: selectedMinute)
            .padding(.top, RadarTradeCardOverlay.railHeight(count: visibleTrades.count, width: plotWidth))
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.018))
                    .shadow(color: .black.opacity(0.09), radius: 5, x: 0, y: 2)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
            }
            .onPreferenceChange(RadarTradeAnchorPreference.self) { tradeAnchors = $0 }
            .overlay {
                RadarTradeCardOverlay(anchors: tradeAnchors, trades: visibleTrades,
                                      currency: displayCurrency)
            }

            HStack(spacing: 14) {
                Label("EMA 9", systemImage: "line.diagonal")
                    .foregroundStyle(.blue)
                Label("EMA 21", systemImage: "line.diagonal")
                    .foregroundStyle(.orange)
                Label("Trend 30", systemImage: "line.diagonal")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            if data.bars.contains(where: { $0.volumeStatus.isReliable }) {
                Chart {
                    ForEach(data.bars.filter { $0.volumeStatus.isReliable }, id: \.minuteEpochSeconds) { bar in
                        BarMark(
                            x: .value("Minute", timeline.position(bar.minuteEpochSeconds)),
                            y: .value("Reported volume", bar.volume)
                        )
                        .foregroundStyle(RadarCandleVisualStyle.body(rising: bar.close >= bar.open))
                        .alignsMarkStylesWithPlotArea(false)
                        .cornerRadius(1.5)
                        .accessibilityLabel(Text(bar.chartDate.formatted(.dateTime.day().month().hour().minute())))
                    }
                    if let selectedBar {
                        RuleMark(x: .value("Selected time", timeline.position(selectedBar.minuteEpochSeconds)))
                            .foregroundStyle(.primary.opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXScale(domain: timeline.domain)
            .chartXAxis { timelineAxis }
                .chartOverlay { proxy in
                    RadarChartCursorOverlay(
                        proxy: proxy, bars: data.bars, timeline: timeline, displayCurrency: displayCurrency, readsPrice: false,
                        selectedBar: selectedBar, selectedPrice: selectedPrice,
                        isPinned: cursorPinned, onSelection: select(bar:price:),
                        onTogglePin: toggleCursorPin, onExit: clearCursor
                    )
                }
                .frame(height: volumeHeight)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.018))
                        .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 1)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
                }
                .accessibilityLabel("Reported minute volume for \(symbol)")
            }
        }
        .onChange(of: symbol) { _, _ in clearCursor() }
        .onChange(of: data.bars.map(\.minuteEpochSeconds)) { _, visibleMinutes in
            if let selectedMinute, !visibleMinutes.contains(selectedMinute) {
                clearCursor()
            }
        }
    }

    @AxisContentBuilder
    private var timelineAxis: some AxisContent {
        AxisMarks(values: timeline.ticks) { value in
            AxisGridLine()
            AxisTick()
            AxisValueLabel {
                if let position = value.as(Double.self), let bar = timeline.bar(at: position) {
                    Text(Date(timeIntervalSince1970: Double(bar.minuteEpochSeconds)),
                         format: data.range.usesDailyBars ? .dateTime.day().month() : .dateTime.day().month().hour().minute())
                }
            }
        }
    }

    private func clearCursor() {
        selectedMinute = nil
        selectedPrice = nil
        cursorPinned = false
        inspection = nil
    }

    private func select(bar: MinuteBar, price: Double) {
        cursorPinned = false
        selectedMinute = bar.minuteEpochSeconds
        selectedPrice = price
        inspection = RadarChartInspection(bar: bar, price: price, isPinned: false)
    }

    private func toggleCursorPin() {
        guard selectedBar != nil else { return }
        cursorPinned.toggle()
        if let selectedBar, let selectedPrice {
            inspection = RadarChartInspection(bar: selectedBar, price: selectedPrice, isPinned: cursorPinned)
        }
    }

    private var priceDomain: ClosedRange<Double> {
        let overlayValues = data.fastEMA.map(\.value) + data.slowEMA.map(\.value) + data.trend30.map(\.value)
        let first = data.bars.first?.minuteEpochSeconds ?? 0
        let last = data.bars.last?.minuteEpochSeconds ?? 0
        let tradePrices = visibleTrades.flatMap { trade -> [Double] in
            var prices: [Double] = []
            if (first...last).contains(trade.entryEpochSeconds) { prices.append(trade.entryPrice) }
            if let exitEpoch = trade.exitEpochSeconds,
               (first...last).contains(exitEpoch), let exitPrice = trade.exitPrice {
                prices.append(exitPrice)
            }
            return prices
        }
        let signalPrices = signal.flatMap { signalIsVisible($0) ? signalEntryPrice : nil }.map { [$0] } ?? []
        let low = (data.bars.map(\.low) + overlayValues + tradePrices + signalPrices).min() ?? 0
        let high = (data.bars.map(\.high) + overlayValues + tradePrices + signalPrices).max() ?? 1
        let padding = max((high - low) * 0.08, high * 0.002)
        return max(0, low - padding)...(high + padding)
    }

    private func signalIsVisible(_ signal: ScanResult) -> Bool {
        guard let first = data.bars.first?.minuteEpochSeconds,
              let last = data.bars.last?.minuteEpochSeconds else { return false }
        let epoch = signal.signalEpochMillis / 1_000
        return epoch >= first - 90 && epoch <= last + 90
    }

    private func signalWindowMinutes(_ signal: ScanResult) -> Int64 {
        Int64(signal.signalWindowLabel.prefix { $0.isNumber }) ?? 1
    }

    @ChartContentBuilder
    private func tradeMarks(for trade: BrokerTradePosition) -> some ChartContent {
        let entryDate = timeline.position(trade.entryEpochSeconds)
        let first = data.bars.first?.minuteEpochSeconds ?? 0
        let last = data.bars.last?.minuteEpochSeconds ?? 0
        let entryVisible = (first...last).contains(trade.entryEpochSeconds)
        let exitVisible = trade.exitEpochSeconds.map { (first...last).contains($0) } == true
        ForEach(data.bars.filter { bar in
            bar.minuteEpochSeconds >= trade.entryEpochSeconds &&
                bar.minuteEpochSeconds <= (trade.exitEpochSeconds ?? Int64.max)
        }, id: \.minuteEpochSeconds) { bar in
            LineMark(x: .value("Owned time", timeline.position(bar.minuteEpochSeconds)),
                     y: .value("Owned price", bar.close), series: .value("Owned interval", "owned-" + trade.id))
                .foregroundStyle(.orange.opacity(0.65))
                .lineStyle(StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
        if entryVisible {
            PointMark(x: .value("Buy time", entryDate), y: .value("Buy price", trade.entryPrice))
                .symbolSize(72)
                .foregroundStyle(.orange)

        }
        if let exitEpoch = trade.exitEpochSeconds,
           let exitPrice = trade.exitPrice,
           exitVisible {
            PointMark(
                x: .value("Sell time", timeline.position(exitEpoch)),
                y: .value("Sell price", exitPrice)
            )
            .symbolSize(72)
            .foregroundStyle(tradeColor(trade))

        }
    }

    private func tradeColor(_ trade: BrokerTradePosition) -> Color {
        guard let profit = trade.profitAmount else { return .orange }
        return profit >= 0 ? .green : .red
    }

}
