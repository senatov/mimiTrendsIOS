import Charts
import SwiftUI

struct LSQuoteHistoryChart: View {
    let symbol: String
    let companyName: String
    let refreshID: Int
    @Binding var range: RadarChartRange
    let signal: ScanResult?
    @Binding var showingSignalFocus: Bool
    @State private var observations: [LSQuoteObservation] = []
    @State private var selectedQuote: LSQuoteObservation?
    @State private var selectedPrice: Double?
    @State private var cursorPinned = false
    @State private var errorMessage: String?

    private var visibleObservations: [LSQuoteObservation] {
        let ranged: [LSQuoteObservation]
        if let seconds = effectiveRange.seconds {
            let cutoff = Int64(Date().timeIntervalSince1970 * 1_000) - seconds * 1_000
            ranged = observations.filter { $0.observedAtMillis >= cutoff }
        } else if effectiveRange == .latest {
            ranged = Array(observations.suffix(60))
        } else {
            ranged = observations
        }
        guard showingSignalFocus, let signal, !ranged.isEmpty else { return ranged }
        let signalMillis = signal.signalEpochMillis
        guard let index = ranged.indices.min(by: {
            abs(ranged[$0].observedAtMillis - signalMillis) < abs(ranged[$1].observedAtMillis - signalMillis)
        }), abs(ranged[index].observedAtMillis - signalMillis) <= 90_000 else { return ranged }
        let lower = max(0, index - 24)
        let upper = ranged.firstIndex { $0.observedAtMillis > signalMillis + 60 * 60_000 } ?? ranged.count
        return Array(ranged[lower..<max(index + 1, upper)])
    }

    private var focusAvailable: Bool {
        guard let signal, let nearest = visibleObservations.min(by: {
            abs($0.observedAtMillis - signal.signalEpochMillis) < abs($1.observedAtMillis - signal.signalEpochMillis)
        }) else { return false }
        return abs(nearest.observedAtMillis - signal.signalEpochMillis) <= 90_000
    }

    private var displayedQuote: LSQuoteObservation? {
        selectedQuote.flatMap { selected in visibleObservations.first { $0.observedAtMillis == selected.observedAtMillis } }
            ?? visibleObservations.last
    }

    private var availableRanges: [RadarChartRange] { [.latest, .oneHour, .threeHours, .oneDay] }
    private var effectiveRange: RadarChartRange { availableRanges.contains(range) ? range : .oneDay }

    private var rangeBinding: Binding<RadarChartRange> {
        Binding(get: { effectiveRange }, set: { range = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 16) {
                    header
                    Divider().frame(height: 20)
                    chartControls
                }
                .frame(minWidth: 0, minHeight: 32)
                .padding(.vertical, 2)
            }
            .fixedSize(horizontal: false, vertical: true)
            if let errorMessage {
                ContentUnavailableView("Quote history unavailable", systemImage: "chart.xyaxis.line",
                                       description: Text(errorMessage))
                    .frame(minHeight: 230)
            } else if visibleObservations.isEmpty {
                ContentUnavailableView("Collecting quote history", systemImage: "chart.xyaxis.line",
                                       description: Text("There are no saved bid and ask samples in this period."))
                    .frame(minHeight: 230)
            } else {
                quoteChart
                HStack(spacing: 12) {
                    Label("Bid", systemImage: "line.diagonal")
                        .foregroundStyle(.teal)
                    Label("Ask", systemImage: "line.diagonal")
                        .foregroundStyle(.orange)
                    Label("EMA 9", systemImage: "line.diagonal").foregroundStyle(.blue)
                    Label("EMA 21", systemImage: "line.diagonal").foregroundStyle(.purple)
                    Label("Trend 30", systemImage: "line.diagonal").foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    Text("Volume unavailable")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsPanel()
        .task(id: "\(symbol)|\(refreshID)|\(range.rawValue)") { await loadHistory() }
        .onChange(of: symbol) { _, _ in clearCursor() }
        .onChange(of: range) { _, _ in clearCursor() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(companyName)
                .font(.headline)
                .help(companyName)
            Text("\(symbol) · EUR")
                .help("Lang & Schwarz quote history")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.indigo)
            if let signal {
                Text("\(signal.signalSource) · \(signal.signalWindowLabel)")
                    .help("Quote movement; volume unavailable")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let quote = displayedQuote {
                Text((selectedPrice ?? quote.midpoint), format: .currency(code: "EUR").precision(.fractionLength(2)))
                    .font(.headline.monospacedDigit())
                    .contentTransition(.numericText())
                Text("BID \(quote.bid.formatted(.currency(code: "EUR").precision(.fractionLength(2))))  ASK \(quote.ask.formatted(.currency(code: "EUR").precision(.fractionLength(2))))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(quoteDate(quote))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.purple)
            }
        }
        .lineLimit(1)
    }

    private var chartControls: some View {
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
                TrendsActionButton(title: "Full history", systemImage: "chart.xyaxis.line",
                                   tint: showingSignalFocus && focusAvailable ? .blue : .purple) {
                    showingSignalFocus = false
                }
                Text("RANGE")
                    .font(.system(.caption2, design: .monospaced).weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                Picker("Chart period", selection: rangeBinding) {
                    ForEach(availableRanges) { option in Text(option.title).tag(option) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 248)
        }
    }

    private var quoteChart: some View {
        Chart {
            if let signal, let first = visibleObservations.first,
               let last = visibleObservations.last,
               signal.signalEpochMillis >= first.observedAtMillis,
               signal.signalEpochMillis <= last.observedAtMillis + 90_000 {
                let minutes = Int(signal.signalWindowLabel.prefix { $0.isNumber }) ?? 1
                let signalEnd = Date(timeIntervalSince1970: Double(signal.signalEpochMillis) / 1_000)
                let signalStart = max(
                    Date(timeIntervalSince1970: Double(first.observedAtMillis) / 1_000),
                    signalEnd.addingTimeInterval(-Double(minutes * 60))
                )
                RectangleMark(
                    xStart: .value("Signal start", signalStart),
                    xEnd: .value("Signal end", signalEnd),
                    yStart: .value("Signal low", priceDomain.lowerBound),
                    yEnd: .value("Signal high", priceDomain.upperBound)
                )
                .foregroundStyle(.orange.opacity(0.08))
                RuleMark(y: .value("Signal entry", signal.signalPrice))
                    .foregroundStyle(.orange.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 3]))
            }
            ForEach(Array(visibleObservations.enumerated()), id: \.offset) { _, quote in
                let date = quoteDateValue(quote)
                LineMark(x: .value("Time", date), y: .value("Bid", quote.bid), series: .value("Side", "Bid"))
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                LineMark(x: .value("Time", date), y: .value("Ask", quote.ask), series: .value("Side", "Ask"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
            ForEach(quoteEMA(period: 9)) { point in
                LineMark(x: .value("Time", point.date), y: .value("Quote EMA 9", point.value),
                         series: .value("Overlay", "EMA 9 · \(point.segment)"))
                    .foregroundStyle(.blue)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
            ForEach(quoteEMA(period: 21)) { point in
                LineMark(x: .value("Time", point.date), y: .value("Quote EMA 21", point.value),
                         series: .value("Overlay", "EMA 21 · \(point.segment)"))
                    .foregroundStyle(.purple)
                    .lineStyle(StrokeStyle(lineWidth: 1.4))
            }
            ForEach(quoteTrend30) { point in
                LineMark(x: .value("Time", point.date), y: .value("Quote Trend 30", point.value),
                         series: .value("Overlay", "Trend 30"))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, lineCap: .round, dash: [6, 4]))
            }
            if let lastQuote = visibleObservations.last {
                RuleMark(y: .value("Current midpoint", lastQuote.midpoint))
                    .foregroundStyle(.teal.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.2, dash: [2, 3]))
                    .annotation(position: .trailing, alignment: .center, spacing: 4) {
                        Text("Current / exit · \(lastQuote.midpoint.formatted(.currency(code: "EUR").precision(.fractionLength(2))))")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 3)
                            .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                    }
            }
            if let selectedQuote, let selectedPrice {
                RuleMark(x: .value("Selected time", quoteDateValue(selectedQuote)))
                    .foregroundStyle(.primary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                RuleMark(y: .value("Selected price", selectedPrice))
                    .foregroundStyle(.primary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                PointMark(x: .value("Selected bid time", quoteDateValue(selectedQuote)),
                          y: .value("Selected bid", selectedQuote.bid))
                    .foregroundStyle(.teal)
                    .symbolSize(42)
                PointMark(x: .value("Selected ask time", quoteDateValue(selectedQuote)),
                          y: .value("Selected ask", selectedQuote.ask))
                    .foregroundStyle(.orange)
                    .symbolSize(42)
            }
        }
        .chartYScale(domain: priceDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                AxisValueLabel(format: .dateTime.hour().minute())
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.16))
                AxisTick()
                AxisValueLabel {
                    if let price = value.as(Double.self) {
                        Text(price.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .chartOverlay { proxy in
            LSQuoteCursorOverlay(
                proxy: proxy, observations: visibleObservations,
                selectedQuote: selectedQuote, selectedPrice: selectedPrice,
                onSelection: { selectedQuote = $0; selectedPrice = $1 },
                isPinned: cursorPinned,
                onTogglePin: { cursorPinned.toggle() },
                onExit: clearCursor
            )
        }
        .frame(minHeight: 260)
        .padding(.top, 4)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.018))
                .shadow(color: .black.opacity(0.08), radius: 5, x: 0, y: 2)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .animation(.easeInOut(duration: 0.22), value: visibleObservations.map(\.observedAtMillis))
        .animation(.easeInOut(duration: 0.18), value: selectedQuote?.observedAtMillis)
    }

    private var priceDomain: ClosedRange<Double> {
        let values = (visibleObservations.flatMap { [$0.bid, $0.ask] } +
            quoteEMA(period: 9).map(\.value) + quoteEMA(period: 21).map(\.value) +
            quoteTrend30.map(\.value) + [signal?.signalPrice].compactMap { $0 }).filter { $0.isFinite }
        let low = values.min() ?? 0
        let high = values.max() ?? (low + 1)
        let padding = max((high - low) * 0.12, abs(high) * 0.001)
        return max(0, low - padding)...(high + padding)
    }

    private func quoteDateValue(_ quote: LSQuoteObservation) -> Date {
        Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)
    }

    private func quoteDate(_ quote: LSQuoteObservation) -> String {
        quoteDateValue(quote).formatted(.dateTime.day().month().hour().minute().second())
    }

    private var quoteTrend30: [RadarQuoteTrendPoint] {
        let values = Array(visibleObservations.suffix(30))
        guard values.count >= 2 else { return [] }
        let count = Double(values.count)
        let meanX = (count - 1) / 2
        let meanY = values.map(\.midpoint).reduce(0, +) / count
        let numerator = values.enumerated().reduce(0.0) {
            $0 + (Double($1.offset) - meanX) * ($1.element.midpoint - meanY)
        }
        let denominator = values.indices.reduce(0.0) { $0 + pow(Double($1) - meanX, 2) }
        guard denominator > 0 else { return [] }
        let slope = numerator / denominator
        return [0, values.count - 1].map { index in
            RadarQuoteTrendPoint(
                quote: values[index], value: meanY + slope * (Double(index) - meanX), segment: 0
            )
        }
    }

    private func quoteEMA(period: Int) -> [RadarQuoteTrendPoint] {
        let smoothing = 2.0 / Double(period + 1)
        var value: Double?
        var previousMillis: Int64?
        var segment = 0
        return visibleObservations.map { quote in
            if let previousMillis, quote.observedAtMillis - previousMillis > 90_000 {
                value = nil
                segment += 1
            }
            value = value.map { quote.midpoint * smoothing + $0 * (1 - smoothing) } ?? quote.midpoint
            previousMillis = quote.observedAtMillis
            return RadarQuoteTrendPoint(quote: quote, value: value ?? quote.midpoint, segment: segment)
        }
    }

    private func loadHistory() async {
        do {
            let requestedSymbol = symbol
            let requestedRange = range
            let loaded = try await Task.detached(priority: .userInitiated) {
                let store = try MarketQuoteStore(url: MarketQuoteStore.defaultURL())
                let now = Int64(Date().timeIntervalSince1970 * 1_000)
                let seconds = min(requestedRange.seconds ?? 3_600, 72 * 3_600)
                return try await store.loadLS(sinceMillis: now - seconds * 1_000)
                    .filter { "LS:" + $0.instrumentID == requestedSymbol }
                    .sorted { $0.observedAtMillis < $1.observedAtMillis }
            }.value
            guard !Task.isCancelled else { return }
            observations = loaded
            errorMessage = nil
        } catch {
            observations = []
            errorMessage = "The saved Lang & Schwarz samples could not be read."
        }
    }

    private func clearCursor() {
        selectedQuote = nil
        selectedPrice = nil
        cursorPinned = false
    }
}

private struct RadarQuoteTrendPoint: Identifiable {
    let quote: LSQuoteObservation
    let value: Double
    let segment: Int
    var id: Int64 { quote.observedAtMillis }
    var date: Date { Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000) }
}

