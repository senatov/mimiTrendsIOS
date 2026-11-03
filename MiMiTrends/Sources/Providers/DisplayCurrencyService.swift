import Foundation

struct DisplayCurrencyRates: Codable, Sendable {
    let date: String
    let ratesPerEuro: [String: Double]
    let fetchedAt: Date

    func convert(_ amount: Double, from source: String, to target: String) -> Double? {
        let source = source.uppercased()
        let target = target.uppercased()
        guard amount.isFinite else { return nil }
        if source == target { return amount }
        guard let sourceRate = ratesPerEuro[source], let targetRate = ratesPerEuro[target],
              sourceRate > 0, targetRate > 0 else { return nil }
        return amount / sourceRate * targetRate
    }

    func formatted(_ amount: Double, from source: String, to target: String) -> String {
        guard let converted = convert(amount, from: source, to: target) else { return "—" }
        return converted.formatted(.currency(code: target).precision(.fractionLength(2)))
    }

    static let supportedCodes = [
        "EUR", "USD", "GBP", "CHF", "JPY", "CAD", "AUD", "NZD", "CNY", "HKD", "SGD",
        "SEK", "NOK", "DKK", "PLN", "CZK", "HUF", "RON", "TRY", "BRL", "MXN",
        "INR", "IDR", "KRW", "MYR", "THB", "PHP", "ZAR", "ILS", "ISK"
    ]
}

actor DisplayCurrencyService {
    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheKey = "display.ecbRates.v1"

    init(session: URLSession = .shared, defaults: UserDefaults = .standard) {
        self.session = session
        self.defaults = defaults
    }

    func cached() -> DisplayCurrencyRates? {
        guard let data = defaults.data(forKey: cacheKey),
              let rates = try? JSONDecoder().decode(DisplayCurrencyRates.self, from: data),
              Date().timeIntervalSince(rates.fetchedAt) < 7 * 86_400 else { return nil }
        return rates
    }

    func latest() async throws -> DisplayCurrencyRates {
        if let cached = cached(), Date().timeIntervalSince(cached.fetchedAt) < 12 * 3_600 { return cached }
        var request = URLRequest(url: URL(string: "https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml")!)
        request.timeoutInterval = 12
        request.setValue("application/xml", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await session.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else {
                throw DisplayCurrencyError.invalidResponse
            }
            let rates = try Self.decode(data, fetchedAt: .now)
            if let encoded = try? JSONEncoder().encode(rates) { defaults.set(encoded, forKey: cacheKey) }
            return rates
        } catch {
            if let cached = cached() { return cached }
            throw error
        }
    }

    static func decode(_ data: Data, fetchedAt: Date) throws -> DisplayCurrencyRates {
        let delegate = ECBRateParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let date = delegate.date, delegate.rates["USD"] != nil else {
            throw DisplayCurrencyError.invalidResponse
        }
        return DisplayCurrencyRates(date: date, ratesPerEuro: delegate.rates, fetchedAt: fetchedAt)
    }
}

private final class ECBRateParser: NSObject, XMLParserDelegate {
    var date: String?
    var rates: [String: Double] = ["EUR": 1]

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes: [String: String]) {
        guard elementName == "Cube" else { return }
        if let time = attributes["time"] { date = time }
        if let code = attributes["currency"], let text = attributes["rate"],
           let rate = Double(text), rate.isFinite, rate > 0 {
            rates[code] = rate
        }
    }
}

enum DisplayCurrencyError: Error { case invalidResponse }

struct IPLocationCurrency: Decodable {
    let success: Bool
    let countryCode: String?
    let currencyCode: String?

    enum CodingKeys: String, CodingKey {
        case success
        case countryCode = "country_code"
        case currencyCode = "currency_code"
    }
}

struct IPLocationCurrencySource: Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) { self.session = session }

    func detect() async throws -> (country: String, currency: String) {
        var request = URLRequest(url: URL(string: "https://ipwhois.app/json/")!)
        request.timeoutInterval = 8
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 30_000,
              let location = try? JSONDecoder().decode(IPLocationCurrency.self, from: data),
              location.success, let country = location.countryCode,
              let currency = location.currencyCode,
              DisplayCurrencyRates.supportedCodes.contains(currency) else {
            throw DisplayCurrencyError.invalidResponse
        }
        return (country, currency)
    }
}
