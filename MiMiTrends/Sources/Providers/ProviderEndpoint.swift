import Foundation

enum ProviderEndpoint: String, CaseIterable, Identifiable {
    case finnhubTrades
    case langSchwarzGermany, langSchwarzStoxx, langSchwarzEurope, langSchwarzAmerica
    case yahooPrimary, yahooAlternate
    case wallstreetOnline, wallstreetWikifolio, wallstreetPerformance, wallstreetGermanPerformance, traderFox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .finnhubTrades: "Live trades"
        case .langSchwarzGermany: "Germany"
        case .langSchwarzStoxx: "STOXX 50"
        case .langSchwarzEurope: "Europe"
        case .langSchwarzAmerica: "America"
        case .yahooPrimary: "Primary"
        case .yahooAlternate: "Alternate"
        case .wallstreetOnline: "Instrument pages"
        case .wallstreetWikifolio: "Wikifolio · today"
        case .wallstreetPerformance: "Trading volume · 24h"
        case .wallstreetGermanPerformance: "Germany · DAX performance"
        case .traderFox: "Market universe"
        }
    }

    var defaultURL: String {
        switch self {
        case .finnhubTrades: "wss://ws.finnhub.io"
        case .langSchwarzGermany: "https://www.ls-tc.de/de/aktien/deutschland"
        case .langSchwarzStoxx: "https://www.ls-tc.de/de/aktien/europa/stoxx50"
        case .langSchwarzEurope: "https://www.ls-tc.de/de/aktien/europa"
        case .langSchwarzAmerica: "https://www.ls-tc.de/de/aktien/amerika"
        case .yahooPrimary: "https://query1.finance.yahoo.com"
        case .yahooAlternate: "https://query2.finance.yahoo.com"
        case .wallstreetOnline: "https://www.wallstreet-online.de"
        case .wallstreetWikifolio: "https://www.wallstreet-online.de/statistik/top-aktien-wikifolio"
        case .wallstreetPerformance: "https://www.wallstreet-online.de/statistik/top-aktien-meistgehandelt"
        case .wallstreetGermanPerformance: "https://www.wallstreet-online.de/statistik/top-dax-aktien-performance"
        case .traderFox: "https://markets.traderfox.com/aktien/"
        }
    }

    var probePath: String {
        switch self {
        case .finnhubTrades: ""
        case .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope, .langSchwarzAmerica: ""
        case .yahooPrimary, .yahooAlternate: "/v1/finance/search?q=ASML&quotesCount=1&newsCount=0"
        case .wallstreetWikifolio, .wallstreetPerformance, .wallstreetGermanPerformance: ""
        case .wallstreetOnline: "/suche/?suche=&q=ASML&sa=Suche"
        case .traderFox: "dax-bestandteile"
        }
    }
}

enum ProviderEndpointError: LocalizedError {
    case invalidURL, checkFailed
    case unexpectedPage(expected: String, detected: String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Enter a secure URL without credentials or a query."
        case .checkFailed: "The provider did not return expected market data."
        case .unexpectedPage(let expected, let detected):
            "This page is a \(detected) ranking. This field expects \(expected)."
        }
    }
}

enum ProviderEndpointStore {
    static func url(for endpoint: ProviderEndpoint, defaults: UserDefaults = .standard) -> URL {
        migrateLegacyRankingURL(defaults: defaults)
        let stored = defaults.string(forKey: key(endpoint)) ?? endpoint.defaultURL
        return (try? validate(stored, for: endpoint)) ?? URL(string: endpoint.defaultURL)!
    }

    static func save(_ value: String, for endpoint: ProviderEndpoint) throws {
        let url = try validate(value, for: endpoint)
        UserDefaults.standard.set(url.absoluteString, forKey: key(endpoint))
    }

    static func removeUnusedLegacyValues(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: "provider.endpoint.finnhubProfiles.v1")
        migrateLegacyRankingURL(defaults: defaults)
    }

    private static func migrateLegacyRankingURL(defaults: UserDefaults) {
        let performanceKey = key(.wallstreetPerformance)
        let stored = defaults.string(forKey: performanceKey)
        let oldValues = [
            "https://www.wallstreet-online.de/statistik/top-aktien-performance",
            "https://www.wallstreet-online.de/statistik/top-aktien-wikifolio"
        ]
        if let stored, oldValues.contains(stored.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) {
            defaults.set(ProviderEndpoint.wallstreetPerformance.defaultURL, forKey: performanceKey)
        }
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
    func check(_ value: String, for endpoint: ProviderEndpoint) async throws -> String {
        let base = try ProviderEndpointStore.validate(value, for: endpoint)
        guard endpoint != .finnhubTrades else {
            throw ProviderEndpointError.checkFailed
        }
        let url = URL(string: endpoint.probePath, relativeTo: base)?.absoluteURL
        guard let url else { throw ProviderEndpointError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 MiMiTrends", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              data.count < 3_000_000 else { throw ProviderEndpointError.checkFailed }
        let body = String(decoding: data, as: UTF8.self)
        if endpoint == .wallstreetGermanPerformance {
            let rows = try WallstreetRankingPageSource.decodeGerman(body)
            return "German ranking table OK · \(rows.count) candidates"
        }
        if endpoint == .wallstreetWikifolio || endpoint == .wallstreetPerformance {
            let kind: WallstreetRankingKind = endpoint == .wallstreetWikifolio ? .wikifolio : .performance
            do {
                let rows = try WallstreetRankingPageSource.decode(body, kind: kind)
                return "Ranking table OK · \(rows.count) candidates"
            } catch {
                let rankingTables = MarketPageHTML.matches(#"<table\b[^>]*>(.*?)</table>"#, in: body)
                func containsTable(_ marker: String) -> Bool {
                    rankingTables.contains { $0.contains("Wertpapier") && $0.contains(marker) }
                }
                let detected: String
                if containsTable("Suchanfragen") {
                    detected = "the most-searched list (/statistik/top-aktien-meistgesucht)"
                } else if containsTable("Käufe/Verkäufe") {
                    detected = "the wikifolio-trading list (/statistik/top-aktien-wikifolio)"
                } else if containsTable("Umsatz") {
                    detected = "the trading-turnover list (/statistik/top-aktien-meistgehandelt)"
                } else {
                    detected = "a page without a recognized ranking table"
                }
                throw ProviderEndpointError.unexpectedPage(
                    expected: endpoint == .wallstreetWikifolio
                        ? "the wikifolio-trading list (/statistik/top-aktien-wikifolio)"
                        : "the trading-turnover list (/statistik/top-aktien-meistgehandelt)",
                    detected: detected
                )
            }
        }
        let expected: String
        switch endpoint {
        case .finnhubTrades: expected = ""
        case .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope, .langSchwarzAmerica:
            expected = "bidWithCurrencySymbol"
        case .yahooPrimary, .yahooAlternate: expected = "quotes"
        case .wallstreetOnline: expected = "ASML"
        case .wallstreetWikifolio: expected = "Käufe/Verkäufe"
        case .wallstreetPerformance: expected = "Umsatz"
        case .wallstreetGermanPerformance: expected = "Perf. %"
        case .traderFox: expected = "equities"
        }
        guard body.localizedCaseInsensitiveContains(expected) else {
            throw ProviderEndpointError.checkFailed
        }
        return "Address reachable · expected response found"
    }
}
