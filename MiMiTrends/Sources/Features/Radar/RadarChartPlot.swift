import Charts
import SwiftUI

struct RadarChartPlot: View {
    let data: RadarChartData
    let symbol: String
    var priceHeight: CGFloat = 300
    var volumeHeight: CGFloat = 90
    @Binding var inspection: RadarChartInspection?
    @State private var selectedMinute: Int64?
    @State private var selectedPrice: Double?
    @State private var cursorPinned = false

    private var selectedBar: MinuteBar? {
        guard let selectedMinute else { return nil }
        return data.bars.first { $0.minuteEpochSeconds == selectedMinute }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                ForEach(data.bars, id: \.minuteEpochSeconds) { bar in
                    let time = Date(timeIntervalSince1970: TimeInterval(bar.minuteEpochSeconds))
                    let color: Color = bar.close >= bar.open ? .green : .red
                    RuleMark(
                        x: .value("Minute", time),
                        yStart: .value("Low", bar.low),
                        yEnd: .value("High", bar.high)
                    )
                    .foregroundStyle(color)
                    RectangleMark(
                        xStart: .value("Start", time.addingTimeInterval(-20)),
                        xEnd: .value("End", time.addingTimeInterval(20)),
                        yStart: .value("Open", bar.open),
                        yEnd: .value("Close", bar.close)
                    )
                    .foregroundStyle(color)
                }
                ForEach(data.fastEMA) { point in
                    LineMark(
                        x: .value("Minute", point.date),
                        y: .value("EMA 9", point.value),
                        series: .value("Overlay segment", "EMA 9-\(point.segment)")
                    )
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                ForEach(data.slowEMA) { point in
                    LineMark(
                        x: .value("Minute", point.date),
                        y: .value("EMA 21", point.value),
                        series: .value("Overlay segment", "EMA 21-\(point.segment)")
                    )
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
                if let selectedBar, let selectedPrice {
                    RuleMark(x: .value("Selected time", selectedBar.chartDate))
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    RuleMark(y: .value("Selected price", selectedPrice))
                        .foregroundStyle(.primary.opacity(0.65))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartYScale(domain: priceDomain)
            .chartXScale(domain: chartTimeDomain)
            .chartOverlay { proxy in
                RadarChartCursorOverlay(
                    proxy: proxy, bars: data.bars, symbol: symbol, readsPrice: true,
                    selectedBar: selectedBar, selectedPrice: selectedPrice,
                    isPinned: cursorPinned, onSelection: select(bar:price:),
                    onTogglePin: toggleCursorPin, onExit: clearCursor
                )
            }
            .frame(height: priceHeight)
            .accessibilityLabel("Saved minute candle chart with EMA 9 and EMA 21 for \(symbol)")

            HStack(spacing: 14) {
                Label("EMA 9", systemImage: "line.diagonal")
                    .foregroundStyle(.blue)
                Label("EMA 21", systemImage: "line.diagonal")
                    .foregroundStyle(.orange)
            }
            .font(.caption)

            if data.bars.contains(where: { $0.volumeStatus.isReliable }) {
                Chart {
                    ForEach(data.bars.filter { $0.volumeStatus.isReliable }, id: \.minuteEpochSeconds) { bar in
                        BarMark(
                            x: .value("Minute", bar.chartDate),
                            y: .value("Reported volume", bar.volume)
                        )
                        .foregroundStyle(bar.close >= bar.open ? .green.opacity(0.55) : .red.opacity(0.55))
                    }
                    if let selectedBar {
                        RuleMark(x: .value("Selected time", selectedBar.chartDate))
                            .foregroundStyle(.primary.opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
                .chartXScale(domain: chartTimeDomain)
                .chartOverlay { proxy in
                    RadarChartCursorOverlay(
                        proxy: proxy, bars: data.bars, symbol: symbol, readsPrice: false,
                        selectedBar: selectedBar, selectedPrice: selectedPrice,
                        isPinned: cursorPinned, onSelection: select(bar:price:),
                        onTogglePin: toggleCursorPin, onExit: clearCursor
                    )
                }
                .frame(height: volumeHeight)
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

    private var chartTimeDomain: ClosedRange<Date> {
        let first = data.bars.first?.chartDate ?? .now.addingTimeInterval(-60)
        let last = data.bars.last?.chartDate ?? .now
        if first == last {
            return first.addingTimeInterval(-30)...last.addingTimeInterval(30)
        }
        return first...last
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
        let overlayValues = data.fastEMA.map(\.value) + data.slowEMA.map(\.value)
        let low = (data.bars.map(\.low) + overlayValues).min() ?? 0
        let high = (data.bars.map(\.high) + overlayValues).max() ?? 1
        let padding = max((high - low) * 0.08, high * 0.002)
        return max(0, low - padding)...(high + padding)
    }
}

private struct RadarChartCursorOverlay: View {
    let proxy: ChartProxy
    let bars: [MinuteBar]
    let symbol: String
    let readsPrice: Bool
    let selectedBar: MinuteBar?
    let selectedPrice: Double?
    let isPinned: Bool
    let onSelection: (MinuteBar, Double) -> Void
    let onTogglePin: () -> Void
    let onExit: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    #if os(macOS)
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let location):
                            if !isPinned { select(at: location, in: geometry) }
                        case .ended:
                            if !isPinned { onExit() }
                        }
                    }
                    .onTapGesture(perform: onTogglePin)
                    #else
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { select(at: $0.location, in: geometry) }
                            .onEnded { _ in onTogglePin() }
                    )
                    #endif
                axisLabels(in: geometry)
            }
        }
    }

    @ViewBuilder
    private func axisLabels(in geometry: GeometryProxy) -> some View {
        if let selectedBar, let selectedPrice, let plotFrameAnchor = proxy.plotFrame {
            let plotFrame = geometry[plotFrameAnchor]
            if readsPrice, let y = proxy.position(forY: selectedPrice) {
                cursorTag(selectedPrice.formatted(.currency(code: chartCurrency).precision(.fractionLength(2))))
                    .position(
                        x: geometry.size.width - 28,
                        y: min(max(plotFrame.minY + y, 14), plotFrame.maxY - 14)
                    )
                    .accessibilityHidden(true)
            } else if !readsPrice, let x = proxy.position(forX: selectedBar.chartDate) {
                cursorTag(selectedBar.chartDate.formatted(
                    .dateTime.day(.twoDigits).month(.twoDigits).year().hour().minute()
                ))
                .position(
                    x: min(max(plotFrame.minX + x, 72), geometry.size.width - 72),
                    y: geometry.size.height - 12
                )
                .accessibilityHidden(true)
            }
        }
    }

    private func cursorTag(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
    }

    private var chartCurrency: String {
        [".DE", ".F", ".PA", ".AS", ".MI", ".HE"].contains(where: symbol.hasSuffix) ? "EUR" : "USD"
    }

    private func select(at location: CGPoint, in geometry: GeometryProxy) {
        guard let plotFrameAnchor = proxy.plotFrame else { return }
        let plotFrame = geometry[plotFrameAnchor]
        guard plotFrame.contains(location) else { return }
        let plotPoint = CGPoint(
            x: location.x - plotFrame.minX,
            y: location.y - plotFrame.minY
        )
        guard let date = proxy.value(atX: plotPoint.x, as: Date.self),
              let bar = RadarChartData.nearestBar(to: date, in: bars) else { return }
        let price = readsPrice
            ? proxy.value(atY: plotPoint.y, as: Double.self) ?? bar.close
            : bar.close
        onSelection(bar, price)
    }
}

private extension MinuteBar {
    var chartDate: Date { Date(timeIntervalSince1970: TimeInterval(minuteEpochSeconds)) }
}
