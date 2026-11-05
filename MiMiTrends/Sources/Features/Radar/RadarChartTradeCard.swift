import SwiftUI

struct RadarChartTradeCard: View {
    let trade: BrokerTradePosition
    let chartCurrency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(trade.symbol) · BUY \(price(trade.entryPrice)) · \(time(trade.entryEpochSeconds))")
            if let exitPrice = trade.exitPrice, let exitEpoch = trade.exitEpochSeconds {
                Text("SELL \(price(exitPrice)) · \(time(exitEpoch))")
                if let profit = trade.profitAmount {
                    let profitText = "\(profit >= 0 ? "+" : "−")\(abs(profit).formatted(.currency(code: chartCurrency).precision(.fractionLength(2))))"
                    let percentText = trade.profitPercent.map {
                        " · \($0 >= 0 ? "+" : "−")\(abs($0).formatted(.number.precision(.fractionLength(2))))%"
                    } ?? ""
                    Text(profitText + percentText)
                        .foregroundStyle(profit >= 0 ? .green : .red)
                }
            } else {
                Text("OPEN · \(trade.quantity.formatted(.number.precision(.fractionLength(0...4)))) shares")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2.monospacedDigit())
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.orange.opacity(0.75), lineWidth: 1))
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private func price(_ value: Double) -> String {
        value.formatted(.currency(code: chartCurrency).precision(.fractionLength(2)))
    }

    private func time(_ epochSeconds: Int64) -> String {
        Date(timeIntervalSince1970: TimeInterval(epochSeconds))
            .formatted(.dateTime.day().month(.twoDigits).hour().minute())
    }
}

