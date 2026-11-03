import Foundation

enum RadarChartCurrency {
    static func source(for symbol: String) -> String {
        [".DE", ".F", ".PA", ".AS", ".MI", ".HE"].contains(where: symbol.uppercased().hasSuffix)
            ? "EUR" : "USD"
    }

    static func bars(_ bars: [MinuteBar], from source: String, to target: String,
                     rates: DisplayCurrencyRates?) -> [MinuteBar]? {
        if source == target { return bars }
        guard let rates, rates.convert(1, from: source, to: target) != nil else { return nil }
        return bars.compactMap { bar in
            guard let open = rates.convert(bar.open, from: source, to: target),
                  let high = rates.convert(bar.high, from: source, to: target),
                  let low = rates.convert(bar.low, from: source, to: target),
                  let close = rates.convert(bar.close, from: source, to: target) else { return nil }
            return MinuteBar(symbol: bar.symbol, minuteEpochSeconds: bar.minuteEpochSeconds,
                             open: open, high: high, low: low, close: close,
                             volume: bar.volume, volumeStatus: bar.volumeStatus)
        }
    }

    static func trade(_ trade: BrokerTradePosition, to target: String,
                      rates: DisplayCurrencyRates?) -> BrokerTradePosition? {
        if trade.currency == target { return trade }
        guard let rates,
              let entry = rates.convert(trade.entryPrice, from: trade.currency, to: target) else { return nil }
        let exit = trade.exitPrice.flatMap { rates.convert($0, from: trade.currency, to: target) }
        let profit = trade.profitAmount.flatMap { rates.convert($0, from: trade.currency, to: target) }
        return BrokerTradePosition(id: trade.id, symbol: trade.symbol, quantity: trade.quantity,
                                   entryEpochSeconds: trade.entryEpochSeconds, entryPrice: entry,
                                   exitEpochSeconds: trade.exitEpochSeconds, exitPrice: exit,
                                   profitAmount: profit, profitPercent: trade.profitPercent,
                                   currency: target)
    }
}
