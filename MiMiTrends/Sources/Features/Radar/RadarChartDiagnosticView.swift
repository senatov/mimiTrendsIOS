import SwiftUI

/// An isolated visual fixture: no network, imported transactions or production writes.
struct RadarChartDiagnosticView: View {
    @State private var inspection: RadarChartInspection?
    private let fixture = RadarChartDiagnosticData()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chart diagnostics · sample trades only").font(.headline)
            Text("Drag a trade card within the rail. Its connector must stay attached to the candle. Use Reset position from the card menu.")
                .font(.callout).foregroundStyle(.secondary)
            ScrollView {
                RadarChartPlot(
                    data: RadarChartData(allBars: fixture.bars, range: .threeHours,
                                        nowEpochSeconds: fixture.now),
                    symbol: "SAMPLE", displayCurrency: "EUR", signal: nil, signalEntryPrice: nil,
                    trades: fixture.trades, priceHeight: 340, volumeHeight: 80, inspection: $inspection
                )
                .padding(12)
            }
            if let inspection {
                Text("Selected \(inspection.bar.minuteEpochSeconds) · \(inspection.price.formatted(.currency(code: "EUR")))")
                    .font(.caption.monospacedDigit())
            }
        }
        .padding(16)
        .frame(minWidth: 800, minHeight: 650)
    }
}

struct RadarChartDiagnosticData {
    let now: Int64 = Int64(Date().timeIntervalSince1970) / 60 * 60

    var bars: [MinuteBar] {
        (0..<90).map { index in
            let open = 100 + Double(index) * 0.035 + sin(Double(index) / 4) * 0.6
            let close = open + cos(Double(index) / 3) * 0.25
            return MinuteBar(symbol: "SAMPLE", minuteEpochSeconds: now - Int64(90 - index) * 60,
                open: open, high: max(open, close) + 0.18, low: min(open, close) - 0.16,
                close: close, volume: 2_000 + Double(index % 11) * 400)
        }
    }

    var trades: [BrokerTradePosition] {
        [BrokerTradePosition(id: "sample-closed", symbol: "SAMPLE", quantity: 10,
            entryEpochSeconds: bars[12].minuteEpochSeconds, entryPrice: bars[12].close,
            exitEpochSeconds: bars[48].minuteEpochSeconds, exitPrice: bars[48].close,
            profitAmount: (bars[48].close - bars[12].close) * 10,
            profitPercent: (bars[48].close / bars[12].close - 1) * 100, currency: "EUR"),
         BrokerTradePosition(id: "sample-open", symbol: "SAMPLE", quantity: 5,
            entryEpochSeconds: bars[70].minuteEpochSeconds, entryPrice: bars[70].close,
            exitEpochSeconds: nil, exitPrice: nil, profitAmount: nil, profitPercent: nil, currency: "EUR")]
    }
}
