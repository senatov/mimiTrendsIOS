import Foundation

enum BrokerTradeChartMatcher {
    static func positions(
        symbol: String,
        companyName: String,
        executions: [BrokerTradeExecution]
    ) -> [BrokerTradePosition] {
        let matching = executions.filter { matches($0, companyName: companyName, symbol: symbol) }
        let currencyGroups = Dictionary(grouping: matching, by: { $0.currency.uppercased() })
        return currencyGroups.values.flatMap { reconcile(symbol: symbol, executions: $0) }
            .sorted { $0.entryEpochSeconds < $1.entryEpochSeconds }
    }

    private static func matches(
        _ execution: BrokerTradeExecution,
        companyName: String,
        symbol: String
    ) -> Bool {
        let transactionName = normalized(execution.description)
        let instrumentName = normalized(companyName)
        let namesMatch = transactionName == instrumentName ||
            transactionName.hasPrefix(instrumentName) || instrumentName.hasPrefix(transactionName)
        if !transactionName.isEmpty, !instrumentName.isEmpty, namesMatch {
            return true
        }
        let ticker = symbol.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ticker.isEmpty else { return false }
        return execution.description.range(
            of: "(?<![A-Z0-9])\(NSRegularExpression.escapedPattern(for: ticker))(?![A-Z0-9])",
            options: .regularExpression.union(.caseInsensitive)
        ) != nil
    }

    private static func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: "\\b(inc|corp|corporation|company|co|plc|ag|se|nv|sa|ltd|the)\\b",
                with: " ", options: .regularExpression
            )
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func reconcile(
        symbol: String,
        executions: [BrokerTradeExecution]
    ) -> [BrokerTradePosition] {
        var lots: [BuyLot] = []
        var positions: [BrokerTradePosition] = []
        let ordered = executions.sorted {
            $0.occurredAtEpochSeconds == $1.occurredAtEpochSeconds
                ? $0.id < $1.id
                : $0.occurredAtEpochSeconds < $1.occurredAtEpochSeconds
        }
        for execution in ordered where execution.shares > 0 {
            if execution.type.caseInsensitiveCompare("Buy") == .orderedSame {
                lots.append(BuyLot(execution))
            } else if execution.type.caseInsensitiveCompare("Sell") == .orderedSame {
                positions.append(contentsOf: closeLots(with: execution, lots: &lots, symbol: symbol))
            }
        }
        positions.append(contentsOf: openPositions(from: lots, symbol: symbol))
        return positions
    }

    private static func closeLots(
        with sell: BrokerTradeExecution,
        lots: inout [BuyLot],
        symbol: String
    ) -> [BrokerTradePosition] {
        var remainingSell = sell.shares
        var closed: [BrokerTradePosition] = []
        while remainingSell > quantityEpsilon, !lots.isEmpty {
            let quantity = min(remainingSell, lots[0].remaining)
            let buySlice = lots[0].take(quantity)
            remainingSell -= quantity
            if let position = closedPosition(buySlice, sell: sell, quantity: quantity, symbol: symbol) {
                closed.append(position)
            }
            if lots[0].remaining <= quantityEpsilon { lots.removeFirst() }
        }
        return closed
    }

    private static func closedPosition(
        _ buy: BuySlice,
        sell: BrokerTradeExecution,
        quantity: Double,
        symbol: String
    ) -> BrokerTradePosition? {
        guard quantity > quantityEpsilon else { return nil }
        let sellAmount = abs(sell.amount) > 0 ? abs(sell.amount) : sell.price * sell.shares
        let sellGross = sellAmount * quantity / sell.shares
        let sellCharges = (sell.fee + sell.tax) * quantity / sell.shares
        let profit = sellGross - sellCharges - buy.gross - buy.charges
        let cost = buy.gross + buy.charges
        return BrokerTradePosition(
            id: "\(buy.execution.id)-\(sell.id)-\(quantity)", symbol: symbol,
            quantity: quantity, entryEpochSeconds: buy.execution.occurredAtEpochSeconds,
            entryPrice: buy.gross / quantity, exitEpochSeconds: sell.occurredAtEpochSeconds,
            exitPrice: sellGross / quantity, profitAmount: profit,
            profitPercent: cost > 0 ? profit / cost * 100 : nil,
            currency: buy.execution.currency
        )
    }

    private static func openPositions(from lots: [BuyLot], symbol: String) -> [BrokerTradePosition] {
        let remaining = lots.filter { $0.remaining > quantityEpsilon }
        guard let first = remaining.first else { return [] }
        let quantity = remaining.reduce(0) { $0 + $1.remaining }
        let gross = remaining.reduce(0) { $0 + $1.grossRemaining }
        return [BrokerTradePosition(
            id: "open-\(first.execution.id)", symbol: symbol, quantity: quantity,
            entryEpochSeconds: first.execution.occurredAtEpochSeconds,
            entryPrice: gross / quantity, exitEpochSeconds: nil, exitPrice: nil,
            profitAmount: nil, profitPercent: nil, currency: first.execution.currency
        )]
    }

    private struct BuyLot {
        let execution: BrokerTradeExecution
        var remaining: Double

        init(_ execution: BrokerTradeExecution) {
            self.execution = execution
            remaining = execution.shares
        }

        var grossRemaining: Double { gross(execution) * remaining / execution.shares }

        mutating func take(_ quantity: Double) -> BuySlice {
            let share = quantity / execution.shares
            remaining = max(0, remaining - quantity)
            return BuySlice(
                execution: execution, quantity: quantity,
                gross: gross(execution) * share,
                charges: (execution.fee + execution.tax) * share
            )
        }
    }

    private struct BuySlice {
        let execution: BrokerTradeExecution
        let quantity: Double
        let gross: Double
        let charges: Double
    }

    private static func gross(_ execution: BrokerTradeExecution) -> Double {
        let amount = abs(execution.amount)
        return amount > 0 ? amount : execution.price * execution.shares
    }

    private static let quantityEpsilon = 0.000_000_1
}
