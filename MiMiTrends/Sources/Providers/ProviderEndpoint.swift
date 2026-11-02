import Foundation

enum ProviderEndpoint: String, CaseIterable, Identifiable {
    case finnhubProfiles, finnhubTrades
    case langSchwarzGermany, langSchwarzStoxx, langSchwarzEurope
    case yahooPrimary, yahooAlternate
    case wallstreetOnline, traderFox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finnhubProfiles: "Company profiles"
        case .finnhubTrades: "Live trades"
        case .langSchwarzGermany: "Germany"
        case .langSchwarzStoxx: "STOXX 50"
        case .langSchwarzEurope: "Europe"
        case .yahooPrimary: "Primary"
        case .yahooAlternate: "Alternate"
        case .wallstreetOnline: "Discovery"
        case .traderFox: "Market universe"
        }
    }

    var defaultURL: String {
        switch self {
        case .finnhubProfiles: "https://finnhub.io"
        case .finnhubTrades: "wss://ws.finnhub.io"
        case .langSchwarzGermany: "https://www.ls-tc.de/de/aktien/deutschland"
        case .langSchwarzStoxx: "https://www.ls-tc.de/de/aktien/europa/stoxx50"
        case .langSchwarzEurope: "https://www.ls-tc.de/de/aktien/europa"
        case .yahooPrimary: "https://query1.finance.yahoo.com"
        case .yahooAlternate: "https://query2.finance.yahoo.com"
        case .wallstreetOnline: "https://www.wallstreet-online.de"
        case .traderFox: "https://markets.traderfox.com/aktien/"
        }
    }

    var isUsedByNativeAdapter: Bool {
        switch self {
        case .finnhubTrades, .yahooPrimary, .yahooAlternate, .traderFox,
             .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope,
             .wallstreetOnline: true
        default: false
        }
    }

    var probePath: String {
        switch self {
        case .finnhubProfiles: "/api/v1/stock/profile2?symbol=ASML"
        case .finnhubTrades: ""
        case .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope: ""
        case .yahooPrimary, .yahooAlternate: "/v1/finance/search?q=ASML&quotesCount=1&newsCount=0"
        case .wallstreetOnline: "/suche/?suche=&q=ASML&sa=Suche"
        case .traderFox: "dax-bestandteile"
        }
    }
}

enum ProviderEndpointError: LocalizedError {
    case invalidURL, checkFailed, missingFinnhubKey

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a secure URL without credentials or a query."
        case .checkFailed: "The provider did not return expected market data."
        case .missingFinnhubKey: "Save a Finnhub API key before checking this endpoint."
        }
    }
}

enum ProviderEndpointStore {
    static func url(for endpoint: ProviderEndpoint) -> URL {
        let stored = UserDefaults.standard.string(forKey: key(endpoint)) ?? endpoint.defaultURL
        return (try? validate(stored, for: endpoint)) ?? URL(string: endpoint.defaultURL)!
    }

    static func save(_ value: String, for endpoint: ProviderEndpoint) throws {
        let url = try validate(value, for: endpoint)
        UserDefaults.standard.set(url.absoluteString, forKey: key(endpoint))
    }

    static func validate(_ value: String, for endpoint: ProviderEndpoint) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == (endpoint == .finnhubTrades ? "wss" : "https"),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = components.url else { throw ProviderEndpointError.invalidURL }
        return url
    }

    private static func key(_ endpoint: ProviderEndpoint) -> String {
        "provider.endpoint.\(endpoint.rawValue).v1"
    }
}

struct ProviderEndpointChecker: Sendable {
    func check(_ value: String, for endpoint: ProviderEndpoint) async throws {
        let base = try ProviderEndpointStore.validate(value, for: endpoint)
        guard endpoint != .finnhubTrades else {
            throw ProviderEndpointError.checkFailed
        }
        let url = URL(string: endpoint.probePath, relativeTo: base)?.absoluteURL
        guard let url else { throw ProviderEndpointError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        if endpoint == .finnhubProfiles {
            guard let key = try FinnhubCredentialStore.load(), !key.isEmpty else {
                throw ProviderEndpointError.missingFinnhubKey
            }
            request.setValue(key, forHTTPHeaderField: "X-Finnhub-Token")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count < 3_000_000 else { throw ProviderEndpointError.checkFailed }
        let body = String(decoding: data, as: UTF8.self)
        let expected: String
        switch endpoint {
        case .finnhubProfiles: expected = "name"
        case .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope: expected = "bidWithCurrencySymbol"
        case .yahooPrimary, .yahooAlternate: expected = "quotes"
        case .wallstreetOnline: expected = "ASML"
        case .traderFox: expected = "equities"
        case .finnhubTrades: expected = ""
        }
        guard body.localizedCaseInsensitiveContains(expected) else {
            throw ProviderEndpointError.checkFailed
        }
    }
}
