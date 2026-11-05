import Foundation

enum RadarSignalPrice {
    struct Presentation: Equatable {
        let text: String
        let explanation: String
        let convertedAmount: Double?
    }

    static func display(_ signal: ScanResult, rates: DisplayCurrencyRates?, currency: String) -> Presentation {
        let sourceCurrency = signal.priceCurrency ?? "USD"
        let sourcePrice = signal.price.formatted(.currency(code: sourceCurrency))
        guard let rates, let converted = rates.convert(signal.price, from: sourceCurrency, to: currency) else {
            if sourceCurrency == currency {
                return Presentation(text: sourcePrice, explanation: "Source price: \(sourcePrice).", convertedAmount: signal.price)
            }
            return Presentation(text: "—", explanation: "Waiting for an ECB rate to convert \(sourceCurrency) to \(currency). Source price: \(sourcePrice).", convertedAmount: nil)
        }
        let text = converted.formatted(.currency(code: currency).precision(.fractionLength(2)))
        return Presentation(text: text,
                            explanation: sourceCurrency == currency ? "Source price: \(sourcePrice)." :
                                "Approximate conversion of \(sourcePrice) using ECB reference rates dated \(rates.date).",
                            convertedAmount: converted)
    }

}
