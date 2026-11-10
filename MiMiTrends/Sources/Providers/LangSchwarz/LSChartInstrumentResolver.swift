import Foundation

/// Links a venue instrument to its primary candle listing by ISIN, never by a shortened name.
actor LSChartInstrumentResolver {
    static let shared = LSChartInstrumentResolver()
    private let session: URLSession
    private var paths: [String: String] = [:]
    private var symbols: [String: String] = [:]

    init(session: URLSession = .shared) { self.session = session }

    func register(_ quotes: [MarketPageQuote]) {
        for quote in quotes { paths["LS:" + quote.identifier] = quote.path }
    }

    func resolve(_ symbol: String) async throws -> String {
        if let cached = symbols[symbol] { return cached }
        guard symbol.hasPrefix("LS:") else { throw RadarSourceError.invalidSymbol }
        if paths[symbol] == nil {
            let quotes = try await LangSchwarzQuoteSource(session: session).loadQuotes()
            register(quotes)
        }
        guard let path = paths[symbol], path.hasPrefix("/de/aktie/"),
              let url = URL(string: "https://www.ls-tc.de" + path) else {
            throw RadarSourceError.invalidSymbol
        }
        let html = String(decoding: try await data(from: url), as: UTF8.self)
        let isin = try Self.isin(in: html)
        var components = URLComponents(url: ProviderEndpointStore.url(for: .yahooPrimary), resolvingAgainstBaseURL: false)!
        components.path = "/v1/finance/search"
        components.queryItems = [URLQueryItem(name: "q", value: isin),
                                 URLQueryItem(name: "quotesCount", value: "10"),
                                 URLQueryItem(name: "newsCount", value: "0")]
        guard let searchURL = components.url else { throw RadarSourceError.invalidResponse }
        let resolved = try Self.yahooSymbol(in: try await data(from: searchURL), isin: isin)
        try Task.checkCancellation()
        symbols[symbol] = resolved
        AppDiagnostics.shared.record(.info, "RadarChart", "ls-candle-symbol-resolved",
                                     "instrument=\(symbol) isin=\(isin) candles=\(resolved)")
        return resolved
    }

    private func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue("MiMiTrends/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw RadarSourceError.invalidResponse }
        if http.statusCode == 429 { throw RadarSourceError.rateLimited }
        guard http.statusCode == 200, data.count <= 3_000_000 else {
            throw RadarSourceError.httpStatus(http.statusCode)
        }
        return data
    }

    static func isin(in html: String) throws -> String {
        guard let title = MarketPageHTML.first(#"<title[^>]*>(.*?)</title>"#, in: html),
              let isin = MarketPageHTML.first(#"\b([A-Z]{2}[A-Z0-9]{9}[0-9])\b"#, in: title) else {
            throw RadarSourceError.invalidResponse
        }
        return isin
    }

    static func yahooSymbol(in data: Data, isin: String) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let quotes = root["quotes"] as? [[String: Any]] else { throw RadarSourceError.invalidResponse }
        let supported = quotes.filter {
            $0["quoteType"] as? String == "EQUITY" &&
                ($0["symbol"] as? String).map(MarketCandidateFilter.supportsYahooBars) == true
        }
        let preferred = isin.hasPrefix("DE") ? supported.filter {
            ($0["symbol"] as? String)?.hasSuffix(".DE") == true
        } : supported.filter { !($0["symbol"] as? String ?? "").hasSuffix(".DE") }
        let matches = preferred.isEmpty ? supported : preferred
        let symbols = Set(matches.compactMap { $0["symbol"] as? String })
        guard symbols.count == 1, let symbol = symbols.first else { throw RadarSourceError.invalidSymbol }
        return symbol
    }
}
