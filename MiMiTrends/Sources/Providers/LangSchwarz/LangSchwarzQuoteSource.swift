import Foundation

struct LangSchwarzQuoteSource: Sendable {
    private let session: URLSession
    private let endpoints: [ProviderEndpoint] = [
        .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope
    ]

    init(session: URLSession = .shared) { self.session = session }

    func loadQuotes() async throws -> [MarketPageQuote] {
        var quotes: [String: MarketPageQuote] = [:]
        var pages: [String] = []
        for endpoint in endpoints {
            try Task.checkCancellation()
            var request = URLRequest(url: ProviderEndpointStore.url(for: endpoint))
            request.timeoutInterval = 15
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("text/html", forHTTPHeaderField: "Accept")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  http.url?.scheme == "https", http.url?.host == "www.ls-tc.de",
                  data.count <= 3_000_000, let html = String(data: data, encoding: .utf8) else {
                throw LangSchwarzQuoteError.invalidPage
            }
            pages.append(html)
        }
        let needsFX = pages.contains { $0.contains("$</span>") || $0.contains("$&nbsp;") }
        let fx = needsFX ? try? await WallstreetOnlineQuoteSource(session: session).loadEURUSD() : nil
        for html in pages {
            let pageQuotes = try Self.decode(html, now: Date(), euroUSD: fx)
            for quote in pageQuotes { quotes[quote.identifier] = quote }
        }
        return quotes.values.sorted { $0.name < $1.name }
    }

    static func decode(_ html: String, now: Date,
                       euroUSD: (rate: Double, observedAt: Int64)? = nil) throws -> [MarketPageQuote] {
        let rows = MarketPageHTML.matches("<tr\\b[^>]*>(.*?)</tr>", in: html)
        guard rows.count >= 10 else { throw LangSchwarzQuoteError.invalidPage }
        let parsed = rows.compactMap { row -> MarketPageQuote? in
            let cells = MarketPageHTML.matches("<td\\b[^>]*>(.*?)</td>", in: row)
            guard cells.count >= 7 else { return nil }
            let wkn = MarketPageHTML.plainText(cells[0]).uppercased()
            guard wkn.range(of: "^[A-Z0-9]{6}$", options: .regularExpression) != nil,
                  let path = MarketPageHTML.first("href=\"(/de/aktie/[a-z0-9-]+)\"", in: cells[1]),
                  let nameHTML = MarketPageHTML.first("<a\\b[^>]*>(.*?)</a>", in: cells[1]),
                  let bidHTML = MarketPageHTML.first("<span\\b[^>]*field=\"bidWithCurrencySymbol\"[^>]*>(.*?)</span>", in: cells[2]),
                  let askHTML = MarketPageHTML.first("<span\\b[^>]*field=\"askWithCurrencySymbol\"[^>]*>(.*?)</span>", in: cells[3]),
                  let bid = MarketPageHTML.germanNumber(bidHTML),
                  let ask = MarketPageHTML.germanNumber(askHTML),
                  let item = MarketPageHTML.first("item=\"([0-9]+)@1\"", in: cells[2]),
                  let time = MarketPageHTML.first("<span\\b[^>]*field=\"midTime\"[^>]*>(.*?)</span>", in: cells[6]),
                  let observed = MarketPageHTML.quoteTime(MarketPageHTML.plainText(time), now: now) else {
                return nil
            }
            let currency: String
            if bidHTML.contains("€") && askHTML.contains("€") { currency = "EUR" }
            else if bidHTML.contains("$") && askHTML.contains("$") { currency = "USD" }
            else { return nil }
            let rate: Double?
            let fxObserved: Int64?
            if currency == "USD" {
                guard let euroUSD, abs(euroUSD.observedAt - observed) <= 5 * 60_000 else { return nil }
                rate = euroUSD.rate
                fxObserved = euroUSD.observedAt
            } else {
                rate = nil
                fxObserved = nil
            }
            let bidEUR = bid / (rate ?? 1)
            let askEUR = ask / (rate ?? 1)
            let quote = MarketPageQuote(identifier: item, name: MarketPageHTML.plainText(nameHTML),
                                        path: path, bidEUR: bidEUR, askEUR: askEUR,
                                        sourceCurrency: currency, sourceBid: bid, sourceAsk: ask,
                                        euroUSDRate: rate, fxObservedAtMillis: fxObserved,
                                        observedAtMillis: observed)
            return quote.isValid ? quote : nil
        }
        guard !parsed.isEmpty else { throw LangSchwarzQuoteError.noFreshQuotes }
        return Dictionary(parsed.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
            .values.sorted { $0.name < $1.name }
    }
}

enum LangSchwarzQuoteError: LocalizedError {
    case invalidPage, noFreshQuotes

    var errorDescription: String? {
        switch self {
        case .invalidPage: "Lang & Schwarz returned an unexpected quote page."
        case .noFreshQuotes: "Lang & Schwarz has no fresh EUR quotes."
        }
    }
}
