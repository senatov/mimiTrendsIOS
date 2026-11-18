import Foundation

enum RadarSignalPrice {
    struct Presentation: Equatable {
        let text: String
        let explanation: String
        let convertedAmount: Double?
    }

    static func display(_ signal: ScanResult, rates: DisplayCurrencyRates?, currency: String) -> Presentation {
        let sourceCurrency = signal.priceCurrency ?? "USD"
        let displayed = signal.currentPrice ?? signal.price
        let sourcePrice = displayed.formatted(.currency(code: sourceCurrency))
        let eventPrice = signal.price.formatted(.currency(code: sourceCurrency))
        let provenance = signal.currentPriceSource.map { "Latest \($0): \(sourcePrice). Event close: \(eventPrice)." }
            ?? "Event close: \(eventPrice). No newer verified price."
        guard let rates, let converted = rates.convert(displayed, from: sourceCurrency, to: currency) else {
            if sourceCurrency == currency {
                return Presentation(text: sourcePrice, explanation: provenance, convertedAmount: displayed)
            }
            return Presentation(text: "—", explanation: "\(provenance) Waiting for an ECB rate to convert \(sourceCurrency) to \(currency).", convertedAmount: nil)
        }
        let text = converted.formatted(.currency(code: currency).precision(.fractionLength(2)))
        return Presentation(text: text,
                            explanation: sourceCurrency == currency ? provenance :
                                "\(provenance) Approximate conversion using ECB reference rates dated \(rates.date).",
                            convertedAmount: converted)
    }

}
