import Charts
import SwiftUI

struct LSQuoteHistoryChart: View {
    let symbol: String
    let companyName: String
    let refreshID: Int
    @State private var observations: [LSQuoteObservation] = []
    @State private var selectedQuote: LSQuoteObservation?
    @State private var selectedPrice: Double?
    @State private var errorMessage: String?

    private var displayedQuote: LSQuoteObservation? { selectedQuote ?? observations.last }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            Text("TIME · EUR · SAMPLED QUOTES")
                .font(.system(.caption2, design: .monospaced).weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            if let errorMessage {
                ContentUnavailableView("Quote history unavailable", systemImage: "chart.xyaxis.line",
                                       description: Text(errorMessage))
                    .frame(minHeight: 230)
            } else if observations.isEmpty {
                ContentUnavailableView("Collecting quote history", systemImage: "chart.xyaxis.line",
                                       description: Text("Bid and ask samples will appear as they are collected."))
                    .frame(minHeight: 230)
            } else {
                quoteChart
                HStack(spacing: 16) {
                    Label("Bid", systemImage: "line.diagonal")
                        .foregroundStyle(.teal)
                    Label("Ask", systemImage: "line.diagonal")
                        .foregroundStyle(.orange)
                    Spacer()
                    Text("Volume unavailable")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .trendsPanel()
        .task(id: "\(symbol)|\(refreshID)") { await loadHistory() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Label("PRICE HISTORY", systemImage: "chart.xyaxis.line")
                    .font(.system(.caption2, design: .monospaced).weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Text(companyName)
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(symbol) · Lang & Schwarz · EUR")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.indigo)
            }
            Spacer(minLength: 8)
            if let quote = displayedQuote {
                VStack(alignment: .trailing, spacing: 5) {
                    Text((selectedPrice ?? quote.midpoint), format: .currency(code: "EUR").precision(.fractionLength(2)))
                        .font(.system(.title2, design: .rounded).weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text("BID \(quote.bid.formatted(.currency(code: "EUR").precision(.fractionLength(2))))  ASK \(quote.ask.formatted(.currency(code: "EUR").precision(.fractionLength(2))))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(quoteDate(quote))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.purple)
                }
                .multilineTextAlignment(.trailing)
            }
        }
    }

    private var quoteChart: some View {
        Chart {
            ForEach(Array(observations.enumerated()), id: \.offset) { _, quote in
                let date = quoteDateValue(quote)
                LineMark(x: .value("Time", date), y: .value("Bid", quote.bid), series: .value("Side", "Bid"))
                    .foregroundStyle(.teal)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                LineMark(x: .value("Time", date), y: .value("Ask", quote.ask), series: .value("Side", "Ask"))
                    .foregroundStyle(.orange)
                    .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
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
                proxy: proxy, observations: observations,
                selectedQuote: selectedQuote, selectedPrice: selectedPrice,
                onSelection: { selectedQuote = $0; selectedPrice = $1 },
                onExit: { selectedQuote = nil; selectedPrice = nil }
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
        .animation(.easeInOut(duration: 0.22), value: observations.count)
        .animation(.easeInOut(duration: 0.22), value: observations.last?.observedAtMillis)
    }

    private var priceDomain: ClosedRange<Double> {
        let values = observations.flatMap { [$0.bid, $0.ask] }.filter { $0.isFinite }
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

    private func loadHistory() async {
        do {
            let requestedSymbol = symbol
            let loaded = try await Task.detached(priority: .userInitiated) {
                let store = try MarketQuoteStore(url: MarketQuoteStore.defaultURL())
                let now = Int64(Date().timeIntervalSince1970 * 1_000)
                return try await store.loadLS(sinceMillis: now - 30 * 60_000)
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
}

private struct LSQuoteCursorOverlay: View {
    let proxy: ChartProxy
    let observations: [LSQuoteObservation]
    let selectedQuote: LSQuoteObservation?
    let selectedPrice: Double?
    let onSelection: (LSQuoteObservation, Double) -> Void
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
                        case .active(let location): select(at: location, in: geometry)
                        case .ended: onExit()
                        }
                    }
                    #else
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { select(at: $0.location, in: geometry) }
                        .onEnded { _ in })
                    #endif
                cursorTags(in: geometry)
            }
        }
    }

    @ViewBuilder
    private func cursorTags(in geometry: GeometryProxy) -> some View {
        if let quote = selectedQuote, let price = selectedPrice, let anchor = proxy.plotFrame {
            let plot = geometry[anchor]
            if let y = proxy.position(forY: price) {
                cursorTag(price.formatted(.currency(code: "EUR").precision(.fractionLength(2))))
                    .position(x: geometry.size.width - 34, y: min(max(plot.minY + y, 16), plot.maxY - 16))
            }
            if let x = proxy.position(forX: Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)) {
                cursorTag(Date(timeIntervalSince1970: Double(quote.observedAtMillis) / 1_000)
                    .formatted(.dateTime.day(.twoDigits).month(.twoDigits).hour().minute().second()))
                    .position(x: min(max(plot.minX + x, 68), geometry.size.width - 68), y: geometry.size.height - 13)
            }
        }
    }

    private func cursorTag(_ value: String) -> some View {
        Text(value)
            .font(.caption2.monospacedDigit())
            .foregroundStyle(TrendsColors.ink)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.yellow.opacity(0.2), in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.blue.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .allowsHitTesting(false)
    }

    private func select(at location: CGPoint, in geometry: GeometryProxy) {
        guard let anchor = proxy.plotFrame else { return }
        let plot = geometry[anchor]
        guard plot.contains(location),
              let x = proxy.value(atX: location.x - plot.minX, as: Date.self),
              let nearest = observations.min(by: {
                  abs($0.observedAtMillis - Int64(x.timeIntervalSince1970 * 1_000)) <
                      abs($1.observedAtMillis - Int64(x.timeIntervalSince1970 * 1_000))
              }) else { return }
        let plotPointY = location.y - plot.minY
        let price = proxy.value(atY: plotPointY, as: Double.self) ?? nearest.midpoint
        onSelection(nearest, price)
    }
}
