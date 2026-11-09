import Foundation

struct LangSchwarzQuoteSource: Sendable {
    private let session: URLSession
    private let endpoints: [ProviderEndpoint] = [
        .langSchwarzGermany, .langSchwarzStoxx, .langSchwarzEurope, .langSchwarzAmerica
    ]

    init(session: URLSession = .shared) { self.session = session }

    func loadQuotes() async throws -> [MarketPageQuote] {
        let pages = await withTaskGroup(of: (ProviderEndpoint, String?).self) { tasks in
            for endpoint in endpoints {
                tasks.addTask { [session] in
                    do {
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
                        return (endpoint, html)
                    } catch {
                        AppDiagnostics.shared.record(.warning, "Lang & Schwarz", "page-fetch-failed",
                            "endpoint=\(endpoint.rawValue) error=\(String(describing: error))")
                        return (endpoint, nil)
                    }
                }
            }
            var result: [(ProviderEndpoint, String)] = []
            for await (endpoint, html) in tasks {
                if let html { result.append((endpoint, html)) }
            }
            return result
        }
        guard !pages.isEmpty else { throw LangSchwarzQuoteError.invalidPage }
        let needsFX = pages.contains { $0.1.contains("$") }
        let fx: (rate: Double, observedAt: Int64)?
        if needsFX {
            do { fx = try await WallstreetOnlineQuoteSource(session: session).loadEURUSD() }
            catch {
                fx = nil
                AppDiagnostics.shared.record(.warning, "Lang & Schwarz", "usd-fx-unavailable",
                    "error=\(String(describing: error)) usdQuotesWillBeSkipped=true")
            }
        } else { fx = nil }
        var quotes: [String: MarketPageQuote] = [:]
        for (endpoint, html) in pages {
            do {
                let decoded = try Self.decode(html, now: Date(), euroUSD: fx)
                for quote in decoded {
                    if let old = quotes[quote.identifier], old.observedAtMillis > quote.observedAtMillis { continue }
                    quotes[quote.identifier] = quote
                }
                AppDiagnostics.shared.record(.info, "Lang & Schwarz", "page-quotes-decoded",
                    "endpoint=\(endpoint.rawValue) quotes=\(decoded.count)")
            } catch {
                AppDiagnostics.shared.record(.warning, "Lang & Schwarz", "page-decode-failed",
                    "endpoint=\(endpoint.rawValue) error=\(String(describing: error))")
            }
        }
        guard !quotes.isEmpty else { throw LangSchwarzQuoteError.noFreshQuotes }
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
