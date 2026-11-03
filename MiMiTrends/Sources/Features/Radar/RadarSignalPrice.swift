import Foundation

enum RadarSignalPrice {
    struct Presentation: Equatable {
        let text: String
        let explanation: String
        let estimatedEUR: Double?
    }

    static func display(_ signal: ScanResult, exchangeRate: FMPExchangeRate?, nowMillis: Int64) -> Presentation {
        // The native signal database predates priceCurrency; all its existing confirmed feeds are US/USD.
        let currency = signal.priceCurrency ?? "USD"
        let sourcePrice = signal.price.formatted(.currency(code: currency))
        guard currency == "USD", let exchangeRate,
              exchangeRate.isUsable(for: signal, nowMillis: nowMillis) else {
            return Presentation(text: sourcePrice, explanation: "Signal price in \(currency): \(sourcePrice).",
                                estimatedEUR: nil)
        }
        let estimatedEUR = signal.price / exchangeRate.eurosToDollars
        let euroPrice = estimatedEUR.formatted(.currency(code: "EUR"))
        let rate = exchangeRate.eurosToDollars.formatted(.number.precision(.fractionLength(4...6)))
        return Presentation(
            text: "≈ \(euroPrice)",
            explanation: "Estimated EUR value \(euroPrice) from signal price \(sourcePrice) using FMP EUR/USD \(rate). This is a currency conversion, not a German exchange quote.",
            estimatedEUR: estimatedEUR
        )
    }
}
